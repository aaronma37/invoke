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
            const size = net.layers[i].in_dim * net.layers[i].num_coeffs * net.layers[i].out_dim;
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
            var avg_grad: f32 = 0.0;
            for (0..grads[l].len) |i| {
                const g = grads[l][i];
                avg_grad += @abs(g);
                self.m[l][i] = self.beta1 * self.m[l][i] + (1.0 - self.beta1) * g;
                self.v[l][i] = self.beta2 * self.v[l][i] + (1.0 - self.beta2) * g * g;
                const update = lr_t * self.m[l][i] / (@sqrt(self.v[l][i]) + self.epsilon);
                net.layers[l].coeffs[i] -= update;
            }
        }
    }
};

pub const KanTrainer = struct {
    const num_threads = 16; 

    pub const ThreadState = struct {
        activations: [][]f32,
        jacobians: [][]f32,
        scratch_grads: [][]f32,
        coeff_grads: [][]f32,
        out_grad: []f32,
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
                const size = net.layers[i].in_dim * net.layers[i].num_coeffs * net.layers[i].out_dim;
                c_grads[i] = try allocator.alloc(f32, size);
            }
            const o_grad = try allocator.alloc(f32, max_chunk_size * net.out_dim);

            return ThreadState{ 
                .activations = acts, 
                .jacobians = jacs, 
                .scratch_grads = s_grads, 
                .coeff_grads = c_grads, 
                .out_grad = o_grad,
                .allocator = allocator 
            };
        }

        pub fn deinit(self: *ThreadState) void {
            for (self.activations) |a| self.allocator.free(a);
            for (self.jacobians) |j| self.allocator.free(j);
            for (self.scratch_grads) |s| self.allocator.free(s);
            for (self.coeff_grads) |c| self.allocator.free(c);
            self.allocator.free(self.out_grad);
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
    lambda_shape: f32 = 1.0,
    lambda_l2: f32 = 0.0001, // Smoothness regularization

    pub fn initFixed(allocator: mem.Allocator, layer_dims: []const usize, num_coeffs: usize, max_chunk_size: usize) !KanTrainer {
        const net = try KanNetwork.init(allocator, layer_dims, num_coeffs);
        const states = try allocator.alloc(ThreadState, num_threads);
        for (0..num_threads) |i| states[i] = try ThreadState.init(allocator, net, max_chunk_size);
        return KanTrainer{
            .net = net,
            .optimizer = try AdamOptimizer.init(allocator, net),
            .allocator = allocator,
            .thread_states = states,
        };
    }

    pub fn initWithNet(allocator: mem.Allocator, net: KanNetwork, max_chunk_size: usize) !KanTrainer {
        const states = try allocator.alloc(ThreadState, num_threads);
        for (0..num_threads) |i| states[i] = try ThreadState.init(allocator, net, max_chunk_size);
        return KanTrainer{
            .net = net,
            .optimizer = try AdamOptimizer.init(allocator, net),
            .allocator = allocator,
            .thread_states = states,
        };
    }

    pub fn deinit(self: *KanTrainer) void {
        for (self.thread_states) |*state| state.deinit();
        self.allocator.free(self.thread_states);
        self.net.deinit();
        self.optimizer.deinit();
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
        const local_inputs = task.batch.inputs[task.start_idx * net.layers[0].in_dim .. task.end_idx * net.layers[0].in_dim];
        const local_targets = task.batch.targets[task.start_idx * net.out_dim .. task.end_idx * net.out_dim];

        var local_activations: [16][]f32 = undefined;
        for (0..net.layers.len + 1) |i| {
            const dim = if (i == 0) net.layers[0].in_dim else net.layers[i-1].out_dim;
            local_activations[i] = state.activations[i][0 .. batch_size * dim];
        }
        var local_scratch: [16][]f32 = undefined;
        for (0..net.layers.len) |i| local_scratch[i] = state.scratch_grads[i][0 .. batch_size * net.layers[i].in_dim];

        for (state.coeff_grads) |g| @memset(g, 0.0);
        
        // Basic Forward
        net.forward(local_inputs, local_activations[0 .. net.layers.len + 1], batch_size);

        const out_grad = state.out_grad[0 .. batch_size * net.out_dim];
        @memset(out_grad, 0.0);

        var loss_acc: f32 = 0.0;
        for (0..batch_size) |b| {
            const pred = local_activations[net.layers.len][b * net.out_dim .. (b + 1) * net.out_dim];
            const target = local_targets[b * net.out_dim .. (b + 1) * net.out_dim];
            const sdf_diff = pred[0] - target[0];
            loss_acc += 0.5 * task.trainer.lambda_shape * sdf_diff * sdf_diff;
            out_grad[b * net.out_dim] = task.trainer.lambda_shape * sdf_diff;
        }
        task.local_loss.* = loss_acc;

        const const_activations = @as([][]const f32, @ptrCast(local_activations[0..net.layers.len+1]));
        net.backward(const_activations, out_grad, state.coeff_grads, local_scratch[0..net.layers.len], batch_size);
    }

    pub fn trainStep(self: *KanTrainer, batch: TrainingBatch) !f32 {
        const batch_size = batch.batch_size;
        const chunk_size = (batch_size + num_threads - 1) / num_threads;
        var thread_losses: [num_threads]f32 = [_]f32{0.0} ** num_threads;
        var threads: [num_threads]std.Thread = undefined;

        for (0..num_threads) |t| {
            const start = t * chunk_size;
            if (start >= batch_size) break;
            const end = @min(start + chunk_size, batch_size);
            threads[t] = try std.Thread.spawn(.{}, trainTaskFunc, .{TrainTask{
                .trainer = self,
                .batch = batch,
                .start_idx = start,
                .end_idx = end,
                .local_loss = &thread_losses[t],
                .state_idx = t,
            }});
        }

        var total_loss: f32 = 0.0;
        for (0..num_threads) |t| {
            if (t * chunk_size < batch_size) {
                threads[t].join();
                total_loss += thread_losses[t];
            }
        }

        // Reduction: Sum and Normalize
        const final_grads = try self.allocator.alloc([]f32, self.net.layers.len);
        for (0..self.net.layers.len) |l| {
            const size = self.net.layers[l].in_dim * self.net.layers[l].num_coeffs * self.net.layers[l].out_dim;
            final_grads[l] = try self.allocator.alloc(f32, size);
            @memset(final_grads[l], 0.0);
            for (0..num_threads) |t| {
                if (t * chunk_size >= batch_size) break;
                for (0..size) |i| final_grads[l][i] += self.thread_states[t].coeff_grads[l][i];
            }

            // NORMALIZE BY BATCH SIZE + CLIP + L2
            const inv_batch = 1.0 / @as(f32, @floatFromInt(batch_size));
            for (final_grads[l], 0..) |*g, i| {
                g.* = (g.* * inv_batch) + (self.net.layers[l].coeffs[i] * self.lambda_l2);
                if (g.* > 1.0) g.* = 1.0;
                if (g.* < -1.0) g.* = -1.0;
            }
        }

        defer { for (final_grads) |g| self.allocator.free(g); self.allocator.free(final_grads); }

        self.optimizer.step(&self.net, final_grads);
        return total_loss / @as(f32, @floatFromInt(batch_size));
    }
};
