function step = newton_solver(grid)

    % Divergence, Gradient and Interpolation
    [D1, G1, I1] = operators(grid.center, 1);
    [D2, G2, I2] = operators(grid.center, 2);
    L = sparse_laplacian(grid.center);
    
    [S, Q, E] = stokes(grid);

    function [rhs, H] = operators(sol)
        % Compute gradients and interpolated values
        I1_C = I1 * sol.C(:); % C on X-staggered grid
        I2_C = I2 * sol.C(:); % C on Y-staggered grid
        G1_Phi = G1 * sol.Phi(:); % dPhi/dx on X-staggered grid
        G2_Phi = G2 * sol.Phi(:); % dPhi/dy on Y-staggered grid
        G1_C = G1 * sol.C(:); % dC/dx on X-staggered grid
        G2_C = G2 * sol.C(:); % dC/dy on Y-staggered grid
        
        % Advection
        P1 = upwind(grid.Vx, sol.Vx, 1); % Choice of upwind cell's face
        P2 = upwind(grid.Vy, sol.Vy, 2); % Choice of upwind cell's face
        
        % Remove ghost points from V grid.
        R1 = P1 * select(grid.Vx.I | shift(grid.Vx.I, [1 0]) | shift(grid.Vx.I, [-1 0]));
        R2 = P2 * select(grid.Vy.I | shift(grid.Vy.I, [0 1]) | shift(grid.Vy.I, [0 -1]));
        R_Vx = R1 * sol.Vx(:);
        R_Vy = R2 * sol.Vy(:);
        PG_Cx = P1 * G1_C;
        PG_Cy = P2 * G2_C;
        V_gradC = R_Vx .* PG_Cx + R_Vy .* PG_Cy; % Advection upwind term

        q = Q * sol.Phi(:); % electric charge (on Stokes' grids)
        e = E * sol.Phi(:); % electric fields (on Stokes' grids)
        
        % Right-Hand Side (operator applied to real- and ghost- values)
        rhs = [D1 * (I1_C .* G1_Phi) + D2 * (I2_C .* G2_Phi); ...
               L - sol.alpha * V_gradC; ...
               S * [sol.Vx(:); sol.Vy(:); sol.P(:)] + q .* e];
           
        H11 = D1 * spdiag(I1_C) * G1 + D2 * spdiag(I2_C) * G2; % Phi
        H12 = D1 * spdiag(G1_Phi) * I1 + D2 * spdiag(G2_Phi) * I2; % C
        H13 = sparse(size(L, 1), size(S, 2)); % V
        
        V_grad = spdiag(R_Vx) * P1 * G1 + spdiag(R_Vy) * P2 * G2;
        gradC_ = [spdiag(PG_Cx) * R1, spdiag(PG_Cy) * R2];
        
        H21 = sparse(size(L, 1), grid.Phi.numel); % Phi
        H22 = L - sol.alpha * V_grad; % C
        H23 = - sol.alpha * [gradC_, sparse(size(L, 1), grid.P.numel)]; % V
        
        H31 = spdiag(q) * E + spdiag(e) * Q; % Phi
        H32 = sparse(size(S, 1), grid.C.numel); % C
        H33 = S; % V

        H = [H11 H12 H13; H21 H22 H23; H31 H32 H33];
    end

    function [sol, H] = boundaries(sol)

        Er = -sol.beta * cos(grid.Phi.y(2:end-1)).';
        dr = grid.Phi.x(end) - grid.Phi.x(end-1);
        Vx_inf = sol.Vinf * cos(grid.Vx.y(2:end-1)).';
        Vy_inf = -sol.Vinf * sin(grid.Vy.y(2:end-1)).';

        Phi = sol.Phi;
        Phi0 = -log( sol.C(2, 2:end-1) ); % Phi = -log(C)
        dPhi0_dC = -1 ./ sol.C(2, 2:end-1); % dPhi/dC = -1/C
        Phi(1, 2:end-1) = Phi0;
        Phi(end, 2:end-1) = Phi(end-1, 2:end-1) + Er * dr;
        Phi(1:end, 1) = Phi(1:end, 2);
        Phi(1:end, end) = Phi(1:end, end-1);
        % Neumann on R=inf
        % Non-linear coupling on R=1
        % Symmetry on Theta=0 & pi.
        H_Phi = symmetries(grid.Phi) * ...
            ([ident(grid.Phi) + coupling(grid.Phi, [1 0]), ...
              coupling(grid.C, [-1 0], dPhi0_dC)]);

        C = sol.C;
        C0 = exp( -sol.Phi(2, 2:end-1) ); % C = exp(-Phi)
        dC0_dPhi = -C0; % dC/dPhi = -exp(-Phi) = -C
        C(1, 2:end-1) = C0;
        C(end, 2:end-1) = 1;
        C(1:end, 1) = C(1:end, 2);
        C(1:end, end) = C(1:end, end-1);
        % Dirichlet (1) on R=inf
        % Non-linear coupling on R=1
        % Symmetry on Theta=0 & pi.
        H_C = symmetries(grid.C) * ...
            ([coupling(grid.Phi, [-1 0], dC0_dPhi), ...
              ident(grid.C)]);

        Vx = sol.Vx;
        Vx(1, 2:end-1) = 0;
        Vx(end, 2:end-1) = Vx_inf;
        Vx(1:end, 1) = Vx(1:end, 2);
        Vx(1:end, end) = Vx(1:end, end-1);
        H_Vx = symmetries(grid.Vx);

        Vy = sol.Vy;

        % Interpolation to R=1
        I = grid.center.I;
        I = shift(I, [-1 0]) & ~I;
        S = select(I) + select( shift(I, [1 0]) ) / 2; % Phi is interpolated on R=1    
        [D, I] = spdiff(true(size(S, 1), 1), 1); % Difference along theta axis.
        IS = I * S;    
        D = spdiag(1 ./ (D * grid.center.y)) * D;
        DS = D * S;
        xi = IS * Phi - log(sol.gamma);

        M1 = 4 * log((exp(xi/2) + 1)/2);
        dM1 = spdiag( 2 ./ (1 + exp(-xi/2)) ) * IS;
        M2 = (DS * sol.Phi);
        dM2 = DS;
        Vs = M1 .* M2;

        Vy(1, 2:end-1) = 2 * Vs - Vy(2, 2:end-1);
        Vy(end, 2:end-1) = Vy_inf;
        Vy(1:end, 1) = 0;
        Vy(1:end, end) = 0;   

        H_Vy = ident(grid.Vy) - coupling(grid.Vy, [-1 0]);
        H_Vy_Phi = 2 * (spdiag(M1) * dM2 + spdiag(M2) * dM1);

        H11 = diag([H_Phi; H_C], H_Vx); % Phi, C, Vx
        H22 = H_Vy; % Vy
        H12 = sparse(size(H11, 1), size(H22, 2)); % 0
        H21 = [H_Vy_Phi, sparse(grid.Vy.I, grid.C.numel + grid.Vx.numel)];

        I = [grid.Phi.I(:); grid.C.I(:); grid.Vx.I(:); grid.Vy.I(:)];
        H = [H11, H12; H21, H22] * expand(I);

        H = diag(H, speye(grid.P.numel)); % no boundaries for P

        sol.Phi = Phi;
        sol.C = C;
        sol.Vx = Vx;
        sol.Vy = Vy;
    end
    function [sol, rhs, du] = newton_step(sol)
        [sol, Hb] = boundaries(sol); % Apply boundary conditions
        [rhs, Hf] = operators(sol); % Apply operators to get RHS        
        % 0 = F(B(u)) + Hf * Hb * du
        % H * du = -F(B(u))
        H = Hf * Hb; % Interior's Hessian
        du = H \ (-sol.rhs);
        sol = apply(sol, du);
    end
    step = @newton_step;

    function sol = apply(sol, du)
        [dPhi, dC, dVx, dVy, dP] = split(du, ...
            grid.Phi.sz-2, grid.C.sz-2, ...
            grid.Vx.sz-2, grid.Vy.sz-2, grid.P.sz);        
        dP = remove_mean(dP);
        sol.Phi(grid.Phi.I) = sol.Phi(grid.Phi.I) + dPhi(:);
        sol.C(grid.C.I) = sol.C(grid.C.I) + dC(:);
        sol.Vx(grid.Vx.I) = sol.Vx(grid.Vx.I) + dVx(:);
        sol.Vy(grid.Vy.I) = sol.Vy(grid.Vy.I) + dVy(:);
        sol.P = remove_mean(sol.P + dP);
    end
end

function x = remove_mean(x)
    x = x - mean(x(:));
end

function S = ghost(I, dir, H)
    if nargin < 3
        H = 1;
    end
    J = ~I & shift(I, dir); % Ghost points
    S = expand(J) * H * select(shift(J, -dir));
end

function S = symmetries(grid)
    J = true(grid.sz);
    J(:, [1 end]) = false;
    S = expand(J) * select(J) + ghost(J, [0 -1]) +  ghost(J, [0 1]);
end

function S = coupling(grid, dir, H)
    S = ghost(grid.I, dir, H);
end

function S = ident(grid)
    K = find(grid.I(:));
    S = sparse(K, K, 1, grid.numel, grid.numel);
end

