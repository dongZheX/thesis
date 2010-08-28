function main1(filename)
    if isempty(filename)
        radius = logspace(0, 3, 50).';
        theta = linspace(0, pi, 30).';
        [center, interior, xstag, ystag] = ...
            grids(radius, theta);
        gridPhi = center;
        gridVx = xstag;
        gridVy = ystag;
        gridP = interior;
        gridC = center;

        solPhi = 0*randn(gridPhi.sz);
        solVx = 0*randn(gridVx.sz);
        solVy = 0*randn(gridVy.sz);
        solP = 0*randn(gridP.sz);
        solC = 1+0*randn(gridC.sz);

        alpha = 1;
        beta = 1e-3;
        gamma = 2;
        Vinf = 1e-2 / (6*pi);
        relax_maxwell = init_maxwell();
        relax_stokes = init_stokes();
        relax_advection = init_advection();    
    else
        load(filename);
    end
    for iter = 1:2000
        relax_maxwell(1);
        relax_stokes(100);
        relax_advection(1);    
        fprintf('\n');
    end
    fprintf('\n');
    % solPhi, solVx, solVy, solP, solC
    F = total_stress(solVx, solVy, solP, radius, theta);
    save(filename)

    function func = init_maxwell()
        maxwell_operator = maxwell_op(gridPhi); % , solC
        [P, Q] = maxwell_boundary_cond(gridPhi, beta);
        A = maxwell_operator * P;
        M = jacobi(gridPhi.sz-2, A);
        func = @relax_maxwell;
        function relax_maxwell(iters)
            q = Q * maxwell_boundary_vec(solC);
            b = maxwell_operator * q;        
            u = solPhi(gridPhi.I);
            [u, e] = relax(M, A, -b, u, iters);
            fprintf('%.5e ', norm(e))
            solPhi = reshape(P*u + q, gridPhi.sz);
        end
    end

    function func = init_stokes()
        stokes_operator = spheric_stokes(gridVx, gridVy, gridP);
        [P, Q] = stokes_boundary_cond(gridVx, gridVy, gridP, Vinf);
        A = stokes_operator * P;        
        q = Q * stokes_boundary_vec(solPhi, solC, interior.y, gamma);
        b = stokes_operator * q;        
        M = stokes_vanka_redblack(gridP.sz, A);
        func = @relax_stokes;
        function relax_stokes(iters)
            u = [solVx(gridVx.I); solVy(gridVy.I); solP(:)];
            [u, e] = relax(M, A, -b, u, iters); % TODO: maxwell_forces(Phi)
            fprintf('%.5e ', norm(e))
            u = P*u + q;
            [solVx, solVy, solP] = split(u, gridVx.sz, gridVy.sz, gridP.sz);
            solP = solP - mean(solP(:));
        end
    end

    function func = init_advection()
        [P, Q] = advection_boundary_cond(gridC, 1);
        L = laplacian(gridC.I, gridC.X, gridC.Y);
        func = @relax_advection;
        function relax_advection(iters)
            VG = advection(gridC.I, gridC.X, gridC.Y, solVx, solVy);
            advect_operator = L - alpha*VG;
            A = advect_operator * P;
            q = Q * advection_boundary_vec(solPhi);
            b = advect_operator * q;
            M = jacobi(gridC.sz-2, A);
            u = solC(gridC.I);
            [u, e] = relax(M, A, -b, u, iters);
            fprintf('%.5e ', norm(e))
            solC = reshape(P*u + q, gridC.sz);
        end
    end
end

function [u, e] = relax(M, A, f, u, iters)
    u0 = u;
    for iter = 1:iters
        for i = 1:numel(M)
            res = f - A*u;
            u = u + M{i}*res;
        end
    end
    e = u - u0;
end

function operator = maxwell_op(gridPhi)
    operator = laplacian(gridPhi.I, gridPhi.X, gridPhi.Y);
end

function [P, Q] = maxwell_boundary_cond(gridPhi, beta)
    [Q1] = dirichlet(gridPhi, [-1 0]); %C
    [P, Q2] = neumann(gridPhi, [+1 0]); %E
    R = symmetry(gridPhi);
    P = R * P * expand(gridPhi.I);
    Einf = beta*cos(gridPhi.y(2:end-1));
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
    R = symmetry(gridVx);
    Px = R * expand(gridVx.I);    
    qx = R * dirichlet(gridVx, [+1 0]) * (-Vinf) * cos(gridVx.y(2:end-1));

    [Py, Qs] = average_dirichlet(gridVy, [-1 0]); % Vslip
    Py = Py * expand(gridVy.I);
    qy = Vinf * dirichlet(gridVy, [+1 0]) * sin(gridVy.y(2:end-1));
    
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
function maxwell_forces(Phi)
end