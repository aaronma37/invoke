const std = @import("std");
const mem = std.mem;
const kan_network = @import("kan_network.zig");
const KanNetwork = kan_network.KanNetwork;
const kan_spline = @import("kan_spline.zig");

/// Data batch for training.
pub const TrainingBatch = struct {
    inputs: []const f32,  // [batch_size * in_dim]
    targets: []const f32, // [batch_size * out_dim]
    batch_size: usize,
};

/// High-performance Adam Optimizer for KAN coefficients.
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
            const layer = net.layers[i];
            const size = layer.out_dim * layer.in_dim * layer.grids[0].coeffs.len;
            m[i] = try allocator.alloc(f32, size);
            v[i] = try allocator.alloc(f32, size);
            @memset(m[i], 0.0);
            @memset(v[i], 0.0);
        }
        
        return AdamOptimizer{
            .m = m,
            .v = v,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AdamOptimizer) void {
        for (self.m) |buf| self.allocator.free(buf);
        for (self.v) |buf| self.allocator.free(buf);
        self.allocator.free(self.m);
        self.allocator.free(self.v);
    }

    pub fn step(self: *AdamOptimizer, net: *KanNetwork, grads: [][]f32) void {
        self.t += 1.0;
        const lr_t = self.learning_rate * @sqrt(1.0 - std.math.pow(f32, self.beta2, self.t)) / (1.0 - std.math.pow(f32, self.beta1, self.t));

        for (0..net.layers.len) |l| {
            const layer = &net.layers[l];
            const num_coeffs = layer.grids[0].coeffs.len;
            const size = layer.out_dim * layer.in_dim * num_coeffs;
            
            for (0..size) |i| {
                const g = grads[l][i];
                self.m[l][i] = self.beta1 * self.m[l][i] + (1.0 - self.beta1) * g;
                self.v[l][i] = self.beta2 * self.v[l][i] + (1.0 - self.beta2) * g * g;
                
                const update = lr_t * self.m[l][i] / (@sqrt(self.v[l][i]) + self.epsilon);
                
                const grid_idx = i / num_coeffs;
                const coeff_idx = i % num_coeffs;
                layer.grids[grid_idx].coeffs[coeff_idx] -= update;
            }
        }
    }
};

pub const KanTrainer = struct {
    net: KanNetwork,
    optimizer: AdamOptimizer,
    allocator: mem.Allocator,

    // Loss weights
    lambda_shape: f32 = 1.0,
    lambda_eikonal: f32 = 0.1,
    lambda_material: f32 = 1.0,

    pub fn init(allocator: mem.Allocator, layer_dims: []const usize, num_coeffs: usize) !KanTrainer {
        const net = try KanNetwork.init(allocator, layer_dims, num_coeffs);
        const optimizer = try AdamOptimizer.init(allocator, net);
        
        return KanTrainer{
            .net = net,
            .optimizer = optimizer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KanTrainer) void {
        self.net.deinit();
        self.optimizer.deinit();
    }

    pub fn trainStep(self: *KanTrainer, batch: TrainingBatch) !f32 {
        const batch_size = batch.batch_size;
        const out_dim = self.net.out_dim;

        // 1. Allocate buffers for forward/backward passes
        const activations = try self.allocator.alloc([]f32, self.net.layers.len + 1);
        defer self.allocator.free(activations);
        for (0..activations.len) |i| {
            const dim = if (i == 0) self.net.layers[0].in_dim else self.net.layers[i-1].out_dim;
            activations[i] = try self.allocator.alloc(f32, batch_size * dim);
        }
        defer for (activations) |a| self.allocator.free(a);

        const coeff_grads = try self.allocator.alloc([]f32, self.net.layers.len);
        defer self.allocator.free(coeff_grads);
        for (0..coeff_grads.len) |i| {
            const size = self.net.layers[i].out_dim * self.net.layers[i].in_dim * self.net.layers[i].grids[0].coeffs.len;
            coeff_grads[i] = try self.allocator.alloc(f32, size);
            @memset(coeff_grads[i], 0.0);
        }
        defer for (coeff_grads) |g| self.allocator.free(g);

        const scratch_grads = try self.allocator.alloc([]f32, self.net.layers.len);
        defer self.allocator.free(scratch_grads);
        for (0..scratch_grads.len) |i| {
            scratch_grads[i] = try self.allocator.alloc(f32, batch_size * self.net.layers[i].in_dim);
        }
        defer for (scratch_grads) |s| self.allocator.free(s);

        const jacobians = try self.allocator.alloc([]f32, self.net.layers.len);
        defer self.allocator.free(jacobians);
        for (0..jacobians.len) |i| {
            jacobians[i] = try self.allocator.alloc(f32, batch_size * self.net.layers[i].out_dim * self.net.layers[i].in_dim);
        }
        defer for (jacobians) |j| self.allocator.free(j);

        // 2. Forward Pass (with Jacobians for Eikonal loss)
        self.net.forwardWithJacobians(batch.inputs, activations, jacobians, batch_size);

        // 3. Loss Calculation & output gradient setup
        const out_grad = try self.allocator.alloc(f32, batch_size * out_dim);
        defer self.allocator.free(out_grad);
        @memset(out_grad, 0.0);

        var total_loss: f32 = 0.0;
        for (0..batch_size) |b| {
            const pred = activations[activations.len - 1][b * out_dim .. (b + 1) * out_dim];
            const target = batch.targets[b * out_dim .. (b + 1) * out_dim];
            
            // Channel 0 is always SDF
            const sdf_diff = pred[0] - target[0];
            total_loss += 0.5 * self.lambda_shape * sdf_diff * sdf_diff;
            out_grad[b * out_dim] = self.lambda_shape * sdf_diff;

            // PBR channels (1-5: R, G, B, Rough, Metal)
            const material_weight = @exp(-@abs(target[0]) * 10.0); // Surface priority
            for (1..out_dim) |j| {
                const diff = pred[j] - target[j];
                total_loss += 0.5 * self.lambda_material * material_weight * diff * diff;
                out_grad[b * out_dim + j] = self.lambda_material * material_weight * diff;
            }
        }

        // 4. Standard Backward Pass
        const const_activations = try self.allocator.alloc([]const f32, activations.len);
        defer self.allocator.free(const_activations);
        for (0..activations.len) |i| const_activations[i] = activations[i];
        
        self.net.backward(const_activations, out_grad, coeff_grads, scratch_grads, batch_size);

        // 5. Eikonal Loss Pass (Enforcing ||grad SDF|| = 1.0)
        // This is a second-order "Double Backprop" pass.
        if (self.lambda_eikonal > 0.0) {
            for (0..batch_size) |b| {
                // First, find the spatial gradient grad_x(SDF) by chaining Jacobians
                var grad_x = [_]f32{ 0.0, 0.0, 0.0 };
                var grad_chain = [_]f32{0.0} ** 64; 
                grad_chain[0] = 1.0; // Start with dLoss/dSDF = 1.0

                var l_idx: usize = self.net.layers.len;
                while (l_idx > 0) : (l_idx -= 1) {
                    const layer_idx = l_idx - 1;
                    const layer = self.net.layers[layer_idx];
                    
                    var next_grad = [_]f32{0.0} ** 64;
                    for (0..layer.in_dim) |in_i| {
                        for (0..layer.out_dim) |out_j| {
                            const J = jacobians[layer_idx][(b * layer.out_dim + out_j) * layer.in_dim + in_i];
                            next_grad[in_i] += grad_chain[out_j] * J;
                        }
                    }
                    grad_chain = next_grad;
                }
                @memcpy(&grad_x, grad_chain[0..3]);

                const norm = @sqrt(grad_x[0]*grad_x[0] + grad_x[1]*grad_x[1] + grad_x[2]*grad_x[2]) + 1e-8;
                const eik_scale = self.lambda_eikonal * (norm - 1.0) / norm;

                // Now backpropagate the Eikonal error (eik_scale * grad_x) to coefficients
                // To do this properly, we use the property that grad_c(J) = basis_prime(x)
                var eik_chain = [_]f32{0.0} ** 64;
                @memcpy(eik_chain[0..3], grad_x[0..3]);

                var l_idx_bp: usize = self.net.layers.len;
                while (l_idx_bp > 0) : (l_idx_bp -= 1) {
                    const layer_idx = l_idx_bp - 1;
                    const layer = self.net.layers[layer_idx];
                    const num_coeffs = layer.grids[0].coeffs.len;
                    
                    var next_eik_chain = [_]f32{0.0} ** 64;

                    for (0..layer.in_dim) |in_i| {
                        const x = activations[layer_idx][b * layer.in_dim + in_i];
                        for (0..layer.out_dim) |out_j| {
                            const grid = layer.grids[out_j * layer.in_dim + in_i];
                            
                            // 1. Update coefficients based on how they affect the gradient magnitude
                            for (0..num_coeffs) |k| {
                                const b_prime = kan_spline.derivative(k, kan_spline.SplineConfig.Order, x, grid.knots);
                                coeff_grads[layer_idx][(out_j * layer.in_dim + in_i) * num_coeffs + k] += eik_scale * eik_chain[in_i] * b_prime;
                            }

                            // 2. Propagate Eikonal error to previous layer's inputs
                            // (This is the second-order backprop through the Jacobian)
                            // For simplicity, we use the layer's stored Jacobian
                            const J = jacobians[layer_idx][(b * layer.out_dim + out_j) * layer.in_dim + in_i];
                            next_eik_chain[in_i] += eik_chain[out_j] * J;
                        }
                    }
                    eik_chain = next_eik_chain;
                }
            }
        }

        // 6. Optimizer Step
        self.optimizer.step(&self.net, coeff_grads);

        return total_loss / @as(f32, @floatFromInt(batch_size));
    }
};

test "KanTrainer: Basic Training Step" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 3, 8, 6 };
    var trainer = try KanTrainer.init(allocator, &dims, 4);
    defer trainer.deinit();

    const batch_size = 4;
    const inputs = try allocator.alloc(f32, batch_size * 3);
    defer allocator.free(inputs);
    @memset(inputs, 0.5);

    const targets = try allocator.alloc(f32, batch_size * 6);
    defer allocator.free(targets);
    @memset(targets, 0.1);

    const batch = TrainingBatch{
        .inputs = inputs,
        .targets = targets,
        .batch_size = batch_size,
    };

    const loss1 = try trainer.trainStep(batch);
    const loss2 = try trainer.trainStep(batch);

    // Loss should decrease after one step
    try std.testing.expect(loss2 < loss1);
}

test "KanTrainer: Numerical Gradient Check" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 4, 1 }; // Simple network for speed
    var trainer = try KanTrainer.init(allocator, &dims, 4);
    defer trainer.deinit();

    const batch_size = 1;
    const inputs = [_]f32{ 0.5, 0.5 };
    const targets = [_]f32{ 0.0 };
    const batch = TrainingBatch{
        .inputs = &inputs,
        .targets = &targets,
        .batch_size = batch_size,
    };

    // 1. Calculate Analytical Gradients
    const activations = try allocator.alloc([]f32, trainer.net.layers.len + 1);
    defer allocator.free(activations);
    for (0..activations.len) |i| {
        const dim = if (i == 0) trainer.net.layers[0].in_dim else trainer.net.layers[i-1].out_dim;
        activations[i] = try allocator.alloc(f32, batch_size * dim);
    }
    defer for (activations) |a| allocator.free(a);

    const coeff_grads = try allocator.alloc([]f32, trainer.net.layers.len);
    defer allocator.free(coeff_grads);
    for (0..coeff_grads.len) |i| {
        const size = trainer.net.layers[i].out_dim * trainer.net.layers[i].in_dim * trainer.net.layers[i].grids[0].coeffs.len;
        coeff_grads[i] = try allocator.alloc(f32, size);
        @memset(coeff_grads[i], 0.0);
    }
    defer for (coeff_grads) |g| allocator.free(g);

    const scratch_grads = try allocator.alloc([]f32, trainer.net.layers.len);
    defer allocator.free(scratch_grads);
    for (0..scratch_grads.len) |i| {
        scratch_grads[i] = try allocator.alloc(f32, batch_size * trainer.net.layers[i].in_dim);
    }
    defer for (scratch_grads) |s| allocator.free(s);

    const jacobians = try allocator.alloc([]f32, trainer.net.layers.len);
    defer allocator.free(jacobians);
    for (0..jacobians.len) |i| {
        jacobians[i] = try allocator.alloc(f32, batch_size * trainer.net.layers[i].out_dim * trainer.net.layers[i].in_dim);
    }
    defer for (jacobians) |j| allocator.free(j);

    trainer.net.forwardWithJacobians(batch.inputs, activations, jacobians, batch_size);
    
    const out_grad = try allocator.alloc(f32, batch_size * trainer.net.out_dim);
    defer allocator.free(out_grad);
    @memset(out_grad, 0.0);
    for (0..batch_size) |b| {
        const pred = activations[activations.len-1][b * trainer.net.out_dim];
        out_grad[b * trainer.net.out_dim] = pred - batch.targets[b * trainer.net.out_dim];
    }
    
    const const_activations = try allocator.alloc([]const f32, activations.len);
    defer allocator.free(const_activations);
    for (0..activations.len) |i| const_activations[i] = activations[i];
    trainer.net.backward(const_activations, out_grad, coeff_grads, scratch_grads, batch_size);

    // 2. Calculate Finite Difference Gradients for a few coefficients
    const eps = @as(f32, 1e-3);
    const layer_idx = 0;
    const coeff_idx = 0;
    
    const original_coeff = trainer.net.layers[layer_idx].grids[0].coeffs[coeff_idx];
    
    // f(x + eps)
    trainer.net.layers[layer_idx].grids[0].coeffs[coeff_idx] = original_coeff + eps;
    trainer.net.forward(batch.inputs, activations, batch_size);
    const pred_plus = activations[activations.len - 1][0];
    const loss_plus = 0.5 * (pred_plus - targets[0]) * (pred_plus - targets[0]);

    // f(x - eps)
    trainer.net.layers[layer_idx].grids[0].coeffs[coeff_idx] = original_coeff - eps;
    trainer.net.forward(batch.inputs, activations, batch_size);
    const pred_minus = activations[activations.len - 1][0];
    const loss_minus = 0.5 * (pred_minus - targets[0]) * (pred_minus - targets[0]);
    
    const numerical_grad = (loss_plus - loss_minus) / (2.0 * eps);
    const analytical_grad = coeff_grads[layer_idx][coeff_idx];

    // Check if they match
    try std.testing.expectApproxEqAbs(numerical_grad, analytical_grad, 1e-3);
}

test "KanTrainer: Eikonal Spatial Gradient Check" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 3, 8, 1 }; // XYZ -> Hidden -> SDF
    var trainer = try KanTrainer.init(allocator, &dims, 4);
    defer trainer.deinit();

    // Set some non-zero coefficients to ensure non-zero gradients
    for (trainer.net.layers) |layer| {
        for (layer.grids) |grid| {
            for (grid.coeffs, 0..) |*c, i| {
                c.* = @as(f32, @floatFromInt(i)) * 0.1;
            }
        }
    }

    const batch_size = 1;
    const inputs = [_]f32{ 0.5, 0.5, 0.5 };
    
    // 1. Calculate Analytical Spatial Gradient (via Jacobians)
    const activations = try allocator.alloc([]f32, trainer.net.layers.len + 1);
    defer allocator.free(activations);
    for (0..activations.len) |i| {
        const dim = if (i == 0) trainer.net.layers[0].in_dim else trainer.net.layers[i-1].out_dim;
        activations[i] = try allocator.alloc(f32, batch_size * dim);
    }
    defer for (activations) |a| allocator.free(a);

    const jacobians = try allocator.alloc([]f32, trainer.net.layers.len);
    defer allocator.free(jacobians);
    for (0..jacobians.len) |i| {
        jacobians[i] = try allocator.alloc(f32, batch_size * trainer.net.layers[i].out_dim * trainer.net.layers[i].in_dim);
    }
    defer for (jacobians) |j| allocator.free(j);

    trainer.net.forwardWithJacobians(&inputs, activations, jacobians, batch_size);
    
    // Chain Jacobians to get grad_x(SDF)
    var grad_chain = [_]f32{0.0} ** 64;
    grad_chain[0] = 1.0; // dSDF/dSDF

    var l_idx: usize = trainer.net.layers.len;
    while (l_idx > 0) : (l_idx -= 1) {
        const layer_idx = l_idx - 1;
        const layer = trainer.net.layers[layer_idx];
        var next_grad = [_]f32{0.0} ** 64;
        for (0..layer.in_dim) |in_i| {
            for (0..layer.out_dim) |out_j| {
                const J = jacobians[layer_idx][out_j * layer.in_dim + in_i];
                next_grad[in_i] += grad_chain[out_j] * J;
            }
        }
        grad_chain = next_grad;
    }
    const analytical_spatial_grad = grad_chain[0..3];

    // 2. Calculate Numerical Spatial Gradient (Finite Difference of input)
    const eps = @as(f32, 1e-3);
    var numerical_spatial_grad: [3]f32 = undefined;
    
    for (0..3) |coord_idx| {
        var inputs_plus = inputs;
        inputs_plus[coord_idx] += eps;
        trainer.net.forward(&inputs_plus, activations, batch_size);
        const sdf_plus = activations[activations.len - 1][0];

        var inputs_minus = inputs;
        inputs_minus[coord_idx] -= eps;
        trainer.net.forward(&inputs_minus, activations, batch_size);
        const sdf_minus = activations[activations.len - 1][0];
        
        numerical_spatial_grad[coord_idx] = (sdf_plus - sdf_minus) / (2.0 * eps);
    }

    // Check if they match
    for (0..3) |i| {
        try std.testing.expectApproxEqAbs(numerical_spatial_grad[i], analytical_spatial_grad[i], 1e-2);
    }
}
