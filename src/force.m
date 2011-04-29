% Electrokinetics Non-Linear Force Solver.
% Usage:
%   betas = 1:0.25:2;     % beta values for continuation solver.
%   sol0 = [];            % Initial solution (empty for beta = 0).
%   velocity = 0.5;       % fluid velocity at infinity.
%   [sol, grid, prof] = main(sol0, betas, velocity); % Run the solver;
%   profview(0, prof);    % Show the profiling data.

function [sol, grid, prof] = force(sol, betas, Vinf, varargin)
    conf = defaults(varargin, ...
        'figures', [], ...
        'version', true, ...
        'profile', false, ...
        'logging', true, ...
        'radius', logspace(0, 3, 60), ...
        'theta', linspace(0, pi, 20), ...
        'gamma', 22.03, ...
        'alpha', 0.0, ...
        'maxres', 1e-10 ...
    );
    
    if conf.version && exist('git', 'file') == 2 % git wrapper function
        [~, ver] = git('log -n1 --format=format:"%h (%ci)"');
        fprintf('\nSolver version %s.\n', ver);
        conf.version = ver;
    end

    % Create grid and initialize the solver
    grid = grids(conf.radius, conf.theta);
    newton_step = solver(grid);
    
    if isempty(sol) % Initial solution
        sigma = 0e-3;
        sol.Phi = sigma*randn(grid.Phi.sz);
        sol.Vx = sigma*randn(grid.Vx.sz);
        sol.Vy = sigma*randn(grid.Vy.sz);
        sol.P = sigma*randn(grid.P.sz);
        sol.C = 1 + sigma*randn(grid.C.sz);
    end
    if isempty(betas) % No iterations are possible if no betas.
        return
    end;
    sol.Vinf = Vinf;
    sol.alpha = conf.alpha;
    sol.gamma = conf.gamma;
    sol.Vinf0 = -2*log((sol.gamma^(1/4) + sol.gamma^(-1/4)) / ...
        (2*sol.gamma^(1/4)));

    k = 1; % iteration index
    if conf.profile
        profile('on');
    end
    while true % Newton's method with continuation in beta.
        sol.beta = betas(min(k, numel(betas)));
        [sol, u, f] = newton_step(sol);
        assert( all(sol.C(:) > 0), 'Negative C.' );
        
        e = norm(f, 2) / norm(u, 2); % Residual norm
        if conf.logging
            fprintf('[%d] B = %e, Residual = %e\n', k, sol.beta, e); 
        end
        
        k = k + 1;
        if e < conf.maxres && k > numel(betas)
            sol = boundaries(sol, grid);
            break;
        end
    end
    sol = total_force(sol, grid);
    sol.grid = grid;
    
    if conf.profile
        profile('off');
    end
    if numel(conf.figures) >= 1
        figure(conf.figures(1));
        show('121', grid.Phi, sol.Phi, '\Phi');
        show('122', grid.C, sol.C, 'C');
        set(gcf, 'Name', 'Numerical Solution')
    end
    if numel(conf.figures) >= 2
        figure(conf.figures(2));
        X = grid.Phi.X;
        Y = grid.Phi.Y;
        show('121', grid.Phi, sol.beta * (0.25*X.^(-2) - X) .* cos(Y), '\Phi');
        show('122', grid.C, 1 + sol.beta * 0.75*X.^(-2) .* cos(Y), 'C');
        set(gcf, 'Name', 'Analytic Solution')
    end
    prof = profile('info');
end

% 3D mesh plot of the solutions
function show(id, grid, sol, msg)
    subplot(id)
    if ~isempty(grid)
        mesh(grid.X, grid.Y, sol)
    else
        mesh(sol)
    end
    title(msg)
end

% variable order: [Phi, C, Vr, Vtheta, P]
% Newton solver iteration for given grid.
function step = solver(grid)

    % Divergence, Gradient and Interpolation
    [D1, G1, I1] = operators(grid.center, 1);
    [D2, G2, I2] = operators(grid.center, 2);
    L = sparse_laplacian(grid.center);
    
    [S, Q, E] = stokes(grid);

    S11 = neumanns(grid.Phi, [1 0], [0 -1], [0 1]);
    S22 = neumanns(grid.C, [0 -1], [0 1]);
    S33 = blkdiag(... % Stokes' part boundary conditions
        neumanns(grid.Vx, [0 -1], [0 1]), ...
        average_dirichlet(grid.Vy, [-1 0]) * expand(grid.Vy.I), ...
        speye(grid.P.numel, grid.P.numel));
    
    % Application of Newton method for given beta
    step = @solver_step;
    function [sol, u, f] = solver_step(sol)
        % Set boundary conditions
        [sol, Qv] = boundaries(sol, grid); 
        
        % Compute gradients and interpolated values
        I1_C = I1 * sol.C(:);
        I2_C = I2 * sol.C(:);
        G1_Phi = G1 * sol.Phi(:);
        G2_Phi = G2 * sol.Phi(:);
        G1_C = G1 * sol.C(:);
        G2_C = G2 * sol.C(:);
        q = Q * sol.Phi(:); % electric charge (on staggered grid)
        e = E * sol.Phi(:); % electric fields (on staggered grid)
        sol.Q = reshape(L * sol.Phi(:), grid.Phi.sz-2);
        
        P1 = upwind(grid.Vx, sol.Vx, 1);
        P2 = upwind(grid.Vy, sol.Vy, 2);
        R1 = select(grid.Vx.I | shift(grid.Vx.I, [1 0]) | shift(grid.Vx.I, [-1 0]));
        R2 = select(grid.Vy.I | shift(grid.Vy.I, [0 1]) | shift(grid.Vy.I, [0 -1]));
        P_Vx = P1 * R1 * sol.Vx(:);
        P_Vy = P2 * R2 * sol.Vy(:);
        P_Cx = P1 * G1_C;
        P_Cy = P2 * G2_C;
        V_gradC = P_Vx .* P_Cx + P_Vy .* P_Cy;

        % f = [div(C grad(Phi)); div(grad(C))] -> 0
        f = [D1 * (I1_C .* G1_Phi) + D2 * (I2_C .* G2_Phi); ...
             D1 * G1_C + D2 * G2_C - sol.alpha * V_gradC; ...
             S * [sol.Vx(:); sol.Vy(:); sol.P(:)] + q .* e]; ...
        
        [H] = hessians(sol); % Laplace-Advection-Stokes Hessian
        dw = -H \ f; % Newton's step
        % Split into various variables' steps
        [dPhi, dC, dVx, dVy, dP] = split(dw, ...
            grid.Phi.sz-2, grid.C.sz-2, ...
            grid.Vx.sz-2, grid.Vy.sz-2, grid.P.sz);        
        dP = dP - mean(dP(:));
        fprintf('<%e %e %e %e %e>\n', norm(dPhi), norm(dC), norm(dVx), norm(dVy), norm(dP))
        sol.Phi(grid.Phi.I) = sol.Phi(grid.Phi.I) + dPhi(:);
        sol.C(grid.C.I) = sol.C(grid.C.I) + dC(:);
        sol.Vx(grid.Vx.I) = sol.Vx(grid.Vx.I) + dVx(:);
        sol.Vy(grid.Vy.I) = sol.Vy(grid.Vy.I) + dVy(:);
        sol.P = sol.P + dP;
        meanP = mean(sol.P(:)); % Zero-mean pressure
        sol.P = sol.P - meanP;
        
        u = [sol.Phi(grid.Phi.I); sol.C(grid.C.I)];
        u = [u; sol.Vx(grid.Vx.I); sol.Vy(grid.Vy.I); sol.P(:)];

        % Hessian matrix
        function [H] = hessians(sol)
            % Phi[0] = -log(C[1])
            S12 = dirichlets(grid.C, [-1 0], -1./sol.C(2, 2:end-1));
            % C[0] = exp(-Phi[1])
            S21 = dirichlets(grid.Phi, [-1 0], -exp(-sol.Phi(2, 2:end-1)));
            % Slipping velocity condition

            % div(C * grad(Phi))
            L1 = D1 * spdiag(I1_C) * G1 + D2 * spdiag(I2_C) * G2; % div(C * grad{x})
            L2 = D1 * spdiag(G1_Phi) * I1 + D2 * spdiag(G2_Phi) * I2; % div(grad(Phi) * {x})
            
            % div(grad(Phi)) * grad(Phi)
            Nstokes = nnz(grid.Vx.I) + nnz(grid.Vy.I) + nnz(grid.P.I);
            S13 = sparse(grid.Phi.numel, Nstokes);
            S23 = sparse(grid.C.numel, Nstokes);
            V_grad = spdiag(P_Vx) * P1 * G1 + spdiag(P_Vy) * P2 * G2;
            gradC = [spdiag(P_Cx) * P1 * R1, spdiag(P_Cy) * P2 * R2, ];
            H1 = [L1, L2; spzeros(size(L)), L - sol.alpha * V_grad] * ... % Hessians
                 [S11, S12, S13; S21, S22, S23]; % Boundary conditions

            Sq = [S11, S12] * 0;
            Qe = spdiag(e)*Q + spdiag(q)*E;
            H2 = [Qe * Sq + S * Qv * Sq, S * S33];
            
            % Stokes' operator [Lalplacian, Grad; Div, 0]            
            H = [H1; H2];
        end
    end
    % Dirichlet for coupled bounadry conditions
    function S = dirichlets(grid, dir, vals)        
        K = find(~grid.I & shift(grid.I, dir)); % ghost points' equations
        I = grid.I & ~shift(grid.I, -dir); 
        J = find(I(2:end-1, 2:end-1)); % near-ghost interior points
        % vals = derivatives of ghost points w.r.t. interior points
        S = sparse(K, J, vals(:), grid.numel, nnz(grid.I));
    end
    % Neumann boundary conditions
    function S = neumanns(grid, varargin)
        S = expand(grid.I);
        for k = 1:numel(varargin)
            d = varargin{k};
            S = neumann(grid, d) * S;
        end
    end
end

% Set boundary conditions
function [sol, Q] = boundaries(sol, grid)
    % Ghost points for R boundaries
    c0 = exp(-sol.Phi(2, 2:end-1));
    phi0 = -log(sol.C(2, 2:end-1));
    dr = grid.Phi.x(end) - grid.Phi.x(end-1);
    Er = -sol.beta * cos(grid.Phi.y(2:end-1)).';
    phi1 = sol.Phi(end-1, 2:end-1) + Er * dr;
    c1 = 1;        
    [sol, Q] = ddslip(sol, grid);
    Vx_inf = sol.Vinf * cos(grid.Vx.y(2:end-1)).';
    Vy_inf = -sol.Vinf * sin(grid.Vy.y(2:end-1)).';

    sol.C(1, 2:end-1) = c0;
    sol.C(end, 2:end-1) = c1;
    sol.C(1:end, 1) = sol.C(1:end, 2);
    sol.C(1:end, end) = sol.C(1:end, end-1);
    
    sol.Phi(1, 2:end-1) = phi0;
    sol.Phi(end, 2:end-1) = phi1;
    sol.Phi(1:end, 1) = sol.Phi(1:end, 2);
    sol.Phi(1:end, end) = sol.Phi(1:end, end-1);
    
    sol.Vx(1, 2:end-1) = 0;
    sol.Vx(end, 2:end-1) = Vx_inf;
    sol.Vx(1:end, 1) = sol.Vx(1:end, 2); % Symmetry for V_r
    sol.Vx(1:end, end) = sol.Vx(1:end, end-1); % Symmetry for V_r
    
    sol.Vy(1, 2:end-1) = 2*sol.Vslip(:).' - sol.Vy(2, 2:end-1);
    sol.Vy(end, 2:end-1) = Vy_inf;
    sol.Vy(1:end, 1) = 0;
    sol.Vy(1:end, end) = 0;
end

function [sol] = total_force(sol, grid)
    radius = grid.radius;
    theta = grid.theta;

    Vx0 = sol.Vx(1:2, :); % radial components
    Vy0 = sol.Vy(1:2, :); % tangential components
    P0 = sol.P(1, :); 
    % grid for computation of (V,P) around R=1.
    grid = grids([2 -1; eye(2)]*radius(1:2), theta);
    stokes_operator = stokes(grid);
    n = numel(grid.P.y); % number of interior cells on R=1.

    % Equations extraction: 
    % * include radial forces and divergence for r<1.
    % * exclude tangential forces and divergence for r>1.
    I = [true(nnz(grid.Vx.I), 1); false(nnz(grid.Vy.I), 1); ...
        repmat([true; false], n, 1)];
    stokes_operator1 = stokes_operator(I, :);

    % Variables extraction:
    % * The unknowns are radial velocities and pressure for r<1.
    J = [col([0 0 0; repmat([1 0 0], n, 1); 0 0 0]'); false(grid.Vy.numel, 1); repmat([1; 0], n, 1)];
    A = stokes_operator1 * expand(J);
    % * All other variables have been computed: 
    %   radial velocities (r>=1), pressures (r>1)
    q = stokes_operator1 * [col([zeros(1, size(Vx0, 2)); Vx0]); ...
                            col([zeros(1, size(Vy0, 2)); Vy0; zeros(1, size(Vy0, 2))]); ...
                            col([0*P0(:) P0(:)]')];
    % Solve A*u + q = 0:
    u = A \ -q;
    % Expand radial velocity and pressure for r<1.
    Vx0 = [u([1, 1:n, n])'; Vx0];
    P0 = [u(n+1:end)'; P0];

    function F = midquad(Fr, Ft)
    % Quadrature (midpoint)
        a = grid.P.y'; % Angle axis (from 0 to pi).
        dF = Fr .* cos(a) - Ft .* sin(a); % Projection on axis of symmetry.
        F = sum( dF' .* (2*pi*sin(grid.P.y)) .* diff(theta));    
    end

    %% Newtonian stress
    % Radial force: -P + 2 dVr/dr
    Fr = -mean(P0) ...
         +2*diff(Vx0([1 3], 2:end-1)) / diff(grid.Vx.x([1 3]));
    % Tangential force: dVt/dr + 1/r {dVr/dt - Vt}
    % NOTE: Vr=0 for r=1.
    Ft =  average(diff(Vy0) / diff(radius(1:2)), [1 1]/2) ...
         -average(Vy0(1:2, :), [1 1; 1 1]/4);

    % Quadrature (midpoint)
    sol.force.newton = midquad(Fr, Ft);    

    %% Maxwell stress
    Phi = sol.Phi(1:2, :);
    dPhi_dr = diff(Phi(:, 2:end-1), 1) / diff(radius(1:2));
    dPhi_dtheta = diff(average(Phi, [1 1; 1 1]/4)) ./ diff(theta.');
    Fr = 1/2 * (dPhi_dr.^2 - dPhi_dtheta.^2);
    Ft = dPhi_dr .* dPhi_dtheta;
    sol.force.maxwell = midquad(Fr, Ft);

    %% Total stress
    sol.force.total = sol.force.newton + sol.force.maxwell;

end

%   Dukhin-Derjaguin slip velocity.
function [sol, Q] = ddslip(sol, grid)
    I1 = grid.center.I;
    I1 = shift(I1, [-1 0]) & ~I1;
    M1 = (select(I1) + select(shift(I1, [1 0]))) / 2; % average on R=1
    I2 = true(nnz(I1), 1);
    M2 = 0.5 * (select(shift(I2, [1 0])) + select(shift(I2, [-1 0])));

    Phi = M1 * sol.Phi(:);

    xi = -M2 * Phi - log(sol.gamma); % log(C/gamma) & Phi = -log(C)
    sol.xi = xi;
    theta = grid.center.y(2:end-1); % interior cells' centers
    
    J = true(numel(theta), 1);
    D = select(shift(J, [1 0])) - select(shift(J, [-1 0]));
    D = spdiag(1 ./ (D * theta)) * D; % Derivation operator.
    
    % Tangential velocity component.
    sol.Vslip = 4 * log((exp(xi/2) + 1)/2) .* (D * Phi);
    
    % Boundary conditions (for Newton method)
    I = [false(grid.Vx.numel, 1); ...
         col(shift(grid.Vy.I, [-1 0]) & ~grid.Vy.I); ...
         false(grid.P.numel, 1)];
    Q = 2 * expand(I);
    Q = Q * 4 * ( spdiag(log((exp(xi/2) + 1)/2)) * D + ...
              spdiag((D * Phi) ./ (exp(-xi/2) + 1)) * (-M2) ...
            ) * M1;
    % d[Vx,Vy,P] = Q * d[Phi]
end

% Create central and staggered grids for Laplace and Stokes problems.
function [grid] = grids(x, y)
    x = x(:); grid.radius = x;
    y = y(:); grid.theta = y;
    % extended grid (for ghost points)
    xg = [2*x(1) - x(2); x; 2*x(end) - x(end-1)];
    yg = [2*y(1) - y(2); y; 2*y(end) - y(end-1)];
    % cell-centered coordinates
    xc = average(xg, [1; 1]/2);
    yc = average(yg, [1; 1]/2);
    
    % NDGRID convention
    grid.center = init_grid(xc, yc);        
    grid.Phi = grid.center;
    grid.C = grid.center;
	grid.Vx = init_grid(xg(2:end-1), yc); % V_r grid
    grid.Vy = init_grid(xc, yg(2:end-1)); % V_theta grid
    grid.P = init_grid(xc(2:end-1), yc(2:end-1), false); % Pressure grid
end

% Splits x into seperate variables according to specified sizes.
%   [x1, x2, x3] = split(x, sz1, sz2, sz3);
%   where sz{i} = size(x{i}) and x = [x1(:); x2(:); x3(:)];
function [varargout] = split(x, varargin)
    N = numel(varargin);
    varargout = cell(N);
    offset = 0;
    for k = 1:N
        sz = varargin{k};
        m = prod(sz);
        varargout{k} = reshape(x(offset + (1:m)), sz);
        offset = offset + m;
    end
    assert(offset == numel(x), 'Splitting mismatch.');
end