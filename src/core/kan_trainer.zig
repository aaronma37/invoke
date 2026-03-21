const std = @import("std");
const mem = std.mem;
const kan_network = @import("kan_network.zig");
const KanNetwork = kan_network.KanNetwork;
const kan_spline = @import("kan_spline.zig");

pub const TrainingBatch = struct {
    inputs: []const f32,
    targets: []const f32,
    batch_size: usize,
};

pub const AdamOptimizer = struct {
    learning_rate: f32 = 0.001,
    beta1: f32 = 0.9,
    beta2: f32 = 0.999,
    epsilon: f32 = 1e-8,
    t: f32 = 0,
    m: [][]f32,
    v: [][]f32,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, net: KanNetwork) !AdamOptimizer {
        const m = try allocator.alloc([]f32, net.layers.len);
        const v = try allocator.alloc([]f32, net.layers.len);
        for (0..net.layers.len) |i| {
            const size = net.layers[i].in_dim * net.layers[i].num_coeffs * net.layers[i].out_dim_padded;
            m[i] = try allocator.alloc(f32, size);
            v[i] = try allocator.alloc(f32, size);
            @memset(m[i], 0.0);
            @memset(v[i], 0.0);
        }
        return AdamOptimizer{ .m = m, .v = v, .allocator = allocator };
    }

    pub fn deinit(self: AdamOptimizer) void {
        for (self.m) |m| self.allocator.free(m);
        for (self.v) |v| self.allocator.free(v);
        self.allocator.free(self.m);
        self.allocator.free(self.v);
    }

    pub fn step(self: *AdamOptimizer, net: *KanNetwork, grads: [][]f32) void {
        self.t += 1;
        const lr_t = self.learning_rate * @sqrt(1.0 - std.math.pow(f32, self.beta2, self.t)) / (1.0 - std.math.pow(f32, self.beta1, self.t));

        for (0..net.layers.len) |l| {
            for (0..grads[l].len) |i| {
                const g = grads[l][i];
                self.m[l][i] = self.beta1 * self.m[l][i] + (1.0 - self.beta1) * g;
                self.v[l][i] = self.beta2 * self.v[l][i] + (1.0 - self.beta2) * g * g;
                const update = lr_t * self.m[l][i] / (@sqrt(self.v[l][i]) + self.epsilon);
                net.layers[l].coeffs[i] -= update;
            }
        }
    }
};

pub const TaskType = enum {
    sdf,
    displacement,
};

pub const KanTrainer = struct {
    pub const ThreadState = struct {
        activations: [][]f32,
        jacobians: [][]f32,
        scratch_grads: [][]f32,
        coeff_grads: [][]f32,
        out_grad: []f32,
        bucket_scratch: []f32,
        allocator: mem.Allocator,

        pub fn init(allocator: mem.Allocator, net: KanNetwork, max_chunk_size: usize) !ThreadState {
            const acts = try allocator.alloc([]f32, net.layers.len + 1);
            for (0..acts.len) |i| {
                const dim = if (i == 0) net.layers[0].in_dim else net.layers[i-1].out_dim;
                acts[i] = try allocator.alloc(f32, max_chunk_size * dim);
            }
            const jacs = try allocator.alloc([]f32, net.layers.len);
            for (0..jacs.len) |i| {
                jacs[i] = try allocator.alloc(f32, max_chunk_size * net.layers[i].out_dim * net.layers[i].in_dim);
            }
            const s_grads = try allocator.alloc([]f32, net.layers.len);
            for (0..s_grads.len) |i| {
                s_grads[i] = try allocator.alloc(f32, max_chunk_size * net.layers[i].in_dim);
            }
            const c_grads = try allocator.alloc([]f32, net.layers.len);
            for (0..c_grads.len) |i| {
                const size = net.layers[i].in_dim * net.layers[i].num_coeffs * net.layers[i].out_dim_padded;
                c_grads[i] = try allocator.alloc(f32, size);
            }
            const o_grad = try allocator.alloc(f32, max_chunk_size * net.out_dim);
            const b_scratch = try allocator.alloc(f32, max_chunk_size); 

            return ThreadState{ 
                .activations = acts, 
                .jacobians = jacs, 
                .scratch_grads = s_grads, 
                .coeff_grads = c_grads, 
                .out_grad = o_grad,
                .bucket_scratch = b_scratch,
                .allocator = allocator 
            };
        }

        pub fn deinit(self: *ThreadState) void {
            for (self.activations) |a| self.allocator.free(a);
            for (self.jacobians) |j| self.allocator.free(j);
            for (self.scratch_grads) |s| self.allocator.free(s);
            for (self.coeff_grads) |c| self.allocator.free(c);
            self.allocator.free(self.out_grad);
            self.allocator.free(self.bucket_scratch);
            self.allocator.free(self.activations);
            self.allocator.free(self.jacobians);
            self.allocator.free(self.scratch_grads);
            self.allocator.free(self.coeff_grads);
        }
    };

    net: KanNetwork,
    optimizer: AdamOptimizer,
    allocator: mem.Allocator,
    thread_states: []ThreadState,
    pool: *std.Thread.Pool,
    num_threads: usize,
    task_type: TaskType = .sdf,
    lambda_shape: f32 = 1.0,
    lambda_l2: f32 = 0.0001,

    pub fn initFixed(allocator: mem.Allocator, layer_dims: []const usize, num_coeffs: usize, max_chunk_size: usize, task: TaskType) !*KanTrainer {
        return initWithThreads(allocator, layer_dims, num_coeffs, max_chunk_size, task, 16);
    }

    pub fn initWithThreads(allocator: mem.Allocator, layer_dims: []const usize, num_coeffs: usize, max_chunk_size: usize, task: TaskType, n_threads: usize) !*KanTrainer {
        const self = try allocator.create(KanTrainer);
        errdefer allocator.destroy(self);

        const net = try KanNetwork.init(allocator, layer_dims, num_coeffs);
        const states = try allocator.alloc(ThreadState, n_threads);
        for (0..n_threads) |i| states[i] = try ThreadState.init(allocator, net, max_chunk_size);
        
        const pool = try allocator.create(std.Thread.Pool);
        errdefer allocator.destroy(pool);
        try pool.init(.{ .allocator = allocator, .n_jobs = n_threads });

        self.* = KanTrainer{
            .net = net,
            .optimizer = try AdamOptimizer.init(allocator, net),
            .allocator = allocator,
            .thread_states = states,
            .pool = pool,
            .num_threads = n_threads,
            .task_type = task,
        };

        return self;
    }

    pub fn initWithNet(allocator: mem.Allocator, net: KanNetwork, max_chunk_size: usize, task: TaskType) !*KanTrainer {
        const n_threads = 16;
        const self = try allocator.create(KanTrainer);
        errdefer allocator.destroy(self);

        const states = try allocator.alloc(ThreadState, n_threads);
        for (0..n_threads) |i| states[i] = try ThreadState.init(allocator, net, max_chunk_size);
        
        const pool = try allocator.create(std.Thread.Pool);
        errdefer allocator.destroy(pool);
        try pool.init(.{ .allocator = allocator, .n_jobs = n_threads });

        self.* = KanTrainer{
            .net = net,
            .optimizer = try AdamOptimizer.init(allocator, net),
            .allocator = allocator,
            .thread_states = states,
            .pool = pool,
            .num_threads = n_threads,
            .task_type = task,
        };

        return self;
    }

    pub fn deinit(self: *KanTrainer) void {
        self.pool.deinit(); 
        self.allocator.destroy(self.pool);
        for (self.thread_states) |*state| state.deinit();
        self.allocator.free(self.thread_states);
        self.net.deinit();
        self.optimizer.deinit();
        self.allocator.destroy(self);
    }

    const TrainTask = struct {
        trainer: *KanTrainer,
        batch: TrainingBatch,
        start_idx: usize,
        end_idx: usize,
        local_loss: *f32,
        state_idx: usize,
    };

    fn trainTaskFunc(task: TrainTask) void {
        const batch_size = task.end_idx - task.start_idx;
        const net = task.trainer.net;
        const state = &task.trainer.thread_states[task.state_idx];
        
        const global_inputs_soa = task.batch.inputs;
        const global_targets_soa = task.batch.targets;

        var local_activations: [16][]f32 = undefined;
        for (0..net.layers.len + 1) |i| {
            const dim = if (i == 0) net.layers[0].in_dim else net.layers[i-1].out_dim;
            local_activations[i] = state.activations[i][0 .. batch_size * dim];
        }
        var local_scratch: [16][]f32 = undefined;
        for (0..net.layers.len) |i| local_scratch[i] = state.scratch_grads[i][0 .. batch_size * net.layers[i].in_dim];

        for (state.coeff_grads) |g| @memset(g, 0.0);
        
        const in_dim = net.layers[0].in_dim;
        const total_batch = task.batch.batch_size;
        for (0..in_dim) |i| {
            const src_row = global_inputs_soa[i * total_batch + task.start_idx .. i * total_batch + task.end_idx];
            @memcpy(local_activations[0][i * batch_size .. (i + 1) * batch_size], src_row);
        }

        net.forward(local_activations[0], local_activations[0 .. net.layers.len + 1], batch_size);

        const out_dim = net.out_dim;
        const final_acts_soa = local_activations[net.layers.len];
        const out_grad_soa = state.out_grad[0 .. batch_size * out_dim];
        @memset(out_grad_soa, 0.0);

        var loss_acc: f32 = 0.0;
        for (0..out_dim) |d| {
            const pred_row = final_acts_soa[d * batch_size .. (d + 1) * batch_size];
            const target_row = global_targets_soa[d * total_batch + task.start_idx .. d * total_batch + task.end_idx];
            const weight = if (task.trainer.task_type == .sdf) (if (d == 0) task.trainer.lambda_shape else 1.0) else 1.0;
            
            for (0..batch_size) |b| {
                const diff = pred_row[b] - target_row[b];
                loss_acc += 0.5 * weight * diff * diff;
                out_grad_soa[d * batch_size + b] = weight * diff;
            }
        }
        task.local_loss.* = loss_acc;

        const const_activations = @as([][]const f32, @ptrCast(local_activations[0..net.layers.len+1]));
        net.backward(const_activations, out_grad_soa, state.coeff_grads, local_scratch[0..net.layers.len], batch_size, state.bucket_scratch);
    }

    fn poolRunWrapper(wait_group: *std.Thread.WaitGroup, task: TrainTask) void {
        defer wait_group.finish();
        trainTaskFunc(task);
    }

    const ThreadLoss = struct {
        val: f32,
        _pad: [15]f32,
    };

    pub fn trainStep(self: *KanTrainer, batch: TrainingBatch) !f32 {
        const batch_size = batch.batch_size;
        const chunk_size = (batch_size + self.num_threads - 1) / self.num_threads;
        
        // We need a way to dynamically size this or use a safe upper bound
        var thread_losses: [64]ThreadLoss = undefined; 
        for (0..self.num_threads) |t| { thread_losses[t].val = 0.0; }
        
        var wg = std.Thread.WaitGroup{};

        for (0..self.num_threads) |t| {
            const start = t * chunk_size;
            if (start >= batch_size) break;
            const end = @min(start + chunk_size, batch_size);
            
            wg.start();
            try self.pool.spawn(poolRunWrapper, .{ &wg, TrainTask{
                .trainer = self,
                .batch = batch,
                .start_idx = start,
                .end_idx = end,
                .local_loss = &thread_losses[t].val,
                .state_idx = t,
            }});
        }

        wg.wait();

        var total_loss: f32 = 0.0;
        for (0..self.num_threads) |t| {
            if (t * chunk_size < batch_size) {
                total_loss += thread_losses[t].val;
            }
        }

        const ccd_threads = if (self.num_threads >= 8) 8 else self.num_threads;
        for (0..self.net.layers.len) |l| {
            const size = self.net.layers[l].in_dim * self.net.layers[l].num_coeffs * self.net.layers[l].out_dim_padded;
            const target_coeffs = self.net.layers[l].coeffs;
            const vec_len = 16;
            const V = @Vector(vec_len, f32);
            
            // CCD0 Reduction
            for (1..ccd_threads) |t| {
                if (t * chunk_size >= batch_size) break;
                const src = self.thread_states[t].coeff_grads[l];
                const acc = self.thread_states[0].coeff_grads[l];
                var i: usize = 0;
                while (i + vec_len <= size) : (i += vec_len) {
                    const v_src: V = src[i..i+vec_len][0..vec_len].*;
                    var v_acc: V = acc[i..i+vec_len][0..vec_len].*;
                    v_acc += v_src;
                    acc[i..i+vec_len][0..vec_len].* = v_acc;
                }
                while (i < size) : (i += 1) { acc[i] += src[i]; }
            }

            // CCD1 Reduction
            if (self.num_threads > ccd_threads) {
                for (ccd_threads + 1 .. self.num_threads) |t| {
                    if (t * chunk_size >= batch_size) break;
                    const src = self.thread_states[t].coeff_grads[l];
                    const acc = self.thread_states[ccd_threads].coeff_grads[l];
                    var i: usize = 0;
                    while (i + vec_len <= size) : (i += vec_len) {
                        const v_src: V = src[i..i+vec_len][0..vec_len].*;
                        var v_acc: V = acc[i..i+vec_len][0..vec_len].*;
                        v_acc += v_src;
                        acc[i..i+vec_len][0..vec_len].* = v_acc;
                    }
                    while (i < size) : (i += 1) { acc[i] += src[i]; }
                }

                // Final merge
                const ccd0_acc = self.thread_states[0].coeff_grads[l];
                const ccd1_acc = self.thread_states[ccd_threads].coeff_grads[l];
                if (ccd_threads * chunk_size < batch_size) {
                    var i: usize = 0;
                    while (i + vec_len <= size) : (i += vec_len) {
                        const v_ccd1: V = ccd1_acc[i..i+vec_len][0..vec_len].*;
                        var v_ccd0: V = ccd0_acc[i..i+vec_len][0..vec_len].*;
                        v_ccd0 += v_ccd1;
                        ccd0_acc[i..i+vec_len][0..vec_len].* = v_ccd0;
                    }
                    while (i < size) : (i += 1) { ccd0_acc[i] += ccd1_acc[i]; }
                }
            }

            const ccd0_acc = self.thread_states[0].coeff_grads[l];
            const inv_batch = 1.0 / @as(f32, @floatFromInt(batch_size));
            var i: usize = 0;
            const v_inv = @as(V, @splat(inv_batch));
            const v_l2 = @as(V, @splat(self.lambda_l2));

            while (i + vec_len <= size) : (i += vec_len) {
                const v_grad: V = ccd0_acc[i..i+vec_len][0..vec_len].*;
                const v_coeffs: V = target_coeffs[i..i+vec_len][0..vec_len].*;
                ccd0_acc[i..i+vec_len][0..vec_len].* = (v_grad * v_inv) + (v_coeffs * v_l2);
            }
            while (i < size) : (i += 1) {
                ccd0_acc[i] = (ccd0_acc[i] * inv_batch) + (target_coeffs[i] * self.lambda_l2);
            }
        }

        self.optimizer.step(&self.net, self.thread_states[0].coeff_grads);
        return total_loss / @as(f32, @floatFromInt(batch_size));
    }
};
