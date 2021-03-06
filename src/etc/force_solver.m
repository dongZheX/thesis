% F = FORCE_SOLVER(FILENAME, MODE, BETA, GAMMA, VINF, RINF, N, 
%                  CYCLES, ITERS)
%
%     Compute the total force acting on a sphere.
%     The solver runs in cycles, applying [iters] to each problem.
%     Problems' parameters are:
%      * field field beta
%      * fluid velocity Vinf
%      * cationic concentration gamma 
%      * radius is logarithmically discretized upto Rinf
%      * the grid is N(1) X N(2)
% 
%     Example:
%       force_solver('results', 1, 0, 2.2, 1e-2, 1e3, ...
%                    [100 30], 50, [false 100 false]);
function F = force_solver(beta, gamma, Vinf, varargin)
    tic;
    opts = struct(varargin{:});
    if opts.quiet
        log = @(varargin) 0;
    else
        log = @fprintf;
    end
    
    radius = logspace(0, log10(opts.Rinf), opts.N(1)).';
    theta = linspace(0, pi, opts.N(2)).';
    [center, interior, xstag, ystag] = grids(radius, theta);
    % Grids for problem's variables
    gridPhi = center;
    gridVx = xstag;
    gridVy = ystag;
    gridP = interior;
    gridC = center;
    % Relaxation operators
    relax_maxwell = init_maxwell();
    relax_stokes = init_stokes();
    relax_advection = init_advection();    

    if isempty(strfind(opts.mode, 'r'))
        solPhi = 0*randn(gridPhi.sz);
        solVx = 0*randn(gridVx.sz);
        solVy = 0*randn(gridVy.sz);
        solP = 0*randn(gridP.sz);
        solC = 1+0*randn(gridC.sz);
        log('Initializing settings for iterative solver.\n');
    else
        S = load(opts.filename);
        solPhi = S.solPhi;
        solVx = S.solVx;
        solVy = S.solVy;
        solP = S.solP;
        solC = S.solC;
        log('Loading solver settings from "%s".\n', opts.filename);
        clear S;
    end
    log('Running solver for %d cycles:\n', opts.cycles);
    log('\tbeta  = %.4e\n', beta);
    log('\tgamma = %.4e\n', gamma);
    log('\tV(inf)  = %.4e\n', Vinf);
    log('\tR(inf)  = %.1f\n', opts.Rinf);
    log('\tGrid size = [%d %d]\n', opts.N(1), opts.N(2));
    res_norm = @(X) norm(X(:), inf);
    
    % Main iteration
    iter_id = 0;
    h = progress([], 0, 'Force Solver');
    function state = iteration(state)
        [solPhi, solVx, solVy, solP, solC] = split(state, ...
            gridPhi.sz, gridVx.sz, gridVy.sz, gridP.sz, gridC.sz);
        res(1) = res_norm(relax_maxwell(opts.iters(1)));
        res(2) = res_norm(relax_stokes(opts.iters(2)));
        res(3) = res_norm(relax_advection(opts.iters(3)));
        iter_id = iter_id + 1;
        s = sprintf('%d: [%.3e  %.3e  %.3e]', iter_id, res(1), res(2), res(3));
        h = progress(h, iter_id/opts.cycles, s);
        state = [solPhi(:); solVx(:); solVy(:); solP(:); solC(:)];
        if any(solC(:) < 0)
            error('ForceSolver:Iteration', 'Negative C!');
        end
    end

    state = [solPhi(:); solVx(:); solVy(:); solP(:); solC(:)];
    
    % Apply specified number of iterations (no extrapolation)
    batch = 1;
    [state] = extrapolate(state, @iteration, ...
        batch-1, ceil(opts.cycles/batch), 'N/A');
    
    [solPhi, solVx, solVy, solP, solC] = split(state, ...
        gridPhi.sz, gridVx.sz, gridVy.sz, gridP.sz, gridC.sz);
    progress(h, []);
    
    log(s);
    log('Iterations done after %.3fs.\n', toc);
    
    F = total_force(solVx, solVy, solP, solPhi, radius, theta);
    log('Total force : %.4e\n', F);
    log('Stokes force : %.4e\n', 6*pi*Vinf);
    if ~isempty(strfind(opts.mode, 'w')) 
        save(opts.filename); 
    end
    log('\n');

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Initialization of problems' operators 
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % Maxwell 
    function func = init_maxwell()
        [P, Q] = maxwell_boundary_cond(gridPhi, beta);
        func = @relax_maxwell;
        function residual = relax_maxwell(iters)           
            residual = NaN; if ~iters, return; end
            maxwell_operator = maxwell_op(gridPhi, solC); % 
            A = maxwell_operator * P;
            M = redblack(gridPhi.sz-2, A);
            q = Q * maxwell_boundary_vec(solC);
            b = maxwell_operator * q;        
            u = solPhi(gridPhi.I);
            [u, residual] = relax(M, A, -b, u, iters);
            solPhi = reshape(P*u + q, gridPhi.sz);
        end
    end
    % Stokes
    function func = init_stokes()
        L = laplacian(gridPhi.I, gridPhi.X, gridPhi.Y);
        Lx = interpolator(gridPhi.X(2:end-1, 2:end-1), gridVx.X(2:end-1, 2:end-1)) * L;
        Ly = interpolator(gridPhi.Y(2:end-1, 2:end-1), gridVy.Y(2:end-1, 2:end-1)) * L;
        grad = @(G, dir) polar_gradient(G.I & shift(G.I, -dir), G.X, G.Y, dir);
        Gx = grad(gridPhi, [1 0]);
        Gy = grad(gridPhi, [0 1]);
        divergence = zeros(gridP.numel, 1);
        function rhs = stokes_rhs(solPhi)
            qx = Lx * solPhi(:);
            qy = Ly * solPhi(:);
            Ex = Gx * solPhi(:);
            Ey = Gy * solPhi(:);
            rhs = [qx .* Ex; qy .* Ey; divergence];
        end

        stokes_operator = spheric_stokes(gridVx, gridVy, gridP);
        [P, Q] = stokes_boundary_cond(gridVx, gridVy, gridP, Vinf);
        A = stokes_operator * P;        
        M = stokes_vanka_redblack(gridP.sz, A);
        func = @relax_stokes;
        function residual = relax_stokes(iters)
            residual = NaN; if ~iters, return; end
            q = Q * stokes_boundary_vec(solPhi, solC, interior.y, gamma);
            b = stokes_operator * q;        
            u = [solVx(gridVx.I); solVy(gridVy.I); solP(:)];
            [u, residual] = relax(M, A, stokes_rhs(solPhi)-b, u, iters);            
            u = P*u + q;
            [solVx, solVy, solP] = split(u, gridVx.sz, gridVy.sz, gridP.sz);
            solP = solP - mean(solP(:));
        end
    end
    % Advection
    function func = init_advection()
        alpha = 1; % Peclet number
        [P, Q] = advection_boundary_cond(gridC, 1);
        L = laplacian(gridC.I, gridC.X, gridC.Y);
        func = @relax_advection;
        function residual = relax_advection(iters)
            residual = NaN; if ~iters, return; end
            VG = advection_upwind(gridC.I, gridC.X, gridC.Y, solVx, solVy, gridVx, gridVy);
            advect_operator = L - alpha*VG;
            A = advect_operator * P;
            q = Q * advection_boundary_vec(solPhi);
            b = advect_operator * q;
            M = redblack(gridC.sz-2, A);
            u = solC(gridC.I);
            [u, residual] = relax(M, A, -b, u, iters);
            solC = reshape(P*u + q, gridC.sz);
        end
    end
end

%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Operators and boundary conditions
function operator = maxwell_op(gridPhi, solC)
    operator = laplacian(gridPhi.I, gridPhi.X, gridPhi.Y, solC);
end

function [P, Q] = maxwell_boundary_cond(gridPhi, beta)
    [Q1] = dirichlet(gridPhi, [-1 0]); %C
    [P, Q2] = neumann(gridPhi, [+1 0]); %E
    R = symmetry(gridPhi);
    P = R * P * expand(gridPhi.I);
    Einf = -beta*cos(gridPhi.y(2:end-1));
    Q = R * [Q1, Q2*Einf];
end
function vec = maxwell_boundary_vec(C)
    vec = [-log(C(2, 2:end-1)).'; 1];
end

function [P, Q] = advection_boundary_cond(gridC, Cinf)
    [Q1] = dirichlet(gridC, [-1 0]); %Phi
    [Q2] = dirichlet(gridC, [+1 0]); %Cinf
    R = symmetry(gridC);
    P = R * expand(gridC.I);
    Cinf = repmat(Cinf, size(Q2, 2), 1);
    Q = R * [Q1, Q2*Cinf];
end
function vec = advection_boundary_vec(Phi)
    C1 = exp(-Phi(2, 2:end-1)).';
    vec = [C1; 1];
end

function [P, Q] = stokes_boundary_cond(gridVx, gridVy, gridP, Vinf)

    [Vx_inf, ~] = stokes_solution(-Vinf, gridVx.x(end), gridVx.y(2:end-1));
    [~, Vy_inf] = stokes_solution(-Vinf, gridVy.x(end), gridVy.y(2:end-1));

    R = symmetry(gridVx);
    Px = R * expand(gridVx.I);            
    qx = R * dirichlet(gridVx, [+1 0]) * Vx_inf;

    [Py, Qs] = average_dirichlet(gridVy, [-1 0]); % Vslip
    Py = Py * expand(gridVy.I);
    qy = dirichlet(gridVy, [+1 0]) * Vy_inf;
    
    P = blkdiag(Px, Py, speye(gridP.numel));
    m = size(Qs, 2);
    Q = [[sparse(gridVx.numel, m); Qs; sparse(gridP.numel, m)], ...
         [qx; qy; sparse(gridP.numel, 1)]];
end
function vec = stokes_boundary_vec(Phi, C, theta, gamma)
    vec = [ddslip(Phi, C, gamma, theta); 1];
end
function R = symmetry(G)
    R = neumann(G, [0 -1], 1) * neumann(G, [0 +1], 1);
end
