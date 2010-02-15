function test
%% Simulate and solve Poisson Equation on a 2D grid using Relaxation
% The equation to solve is: Laplacian(u) = f.
% Laplacian is discretized on a grid, and Jacobi iteration is used for solution.

clc
sz = [17 9]; % We use NDGRID convention (X is 1st, Y is 2nd)
[X, Y] = create_grid( linspace(-2, 2, sz(1)), linspace(-1, 1, sz(2)) );
[U, L] = create_sol(); % The ideal solution and its Laplacian.

% We actually solve the linear system: Av = f
[A, I] = create_laplacian(X, Y, sz);
V0 = U(X, Y); % The ideal solution (for boundary condition)
V0(I) = 0; % "Fill" the interior with initial guess
F = L(X, Y); % right hand side of the equation
V = jacobi(A, V0, F, I, 100)
mesh(X, Y, V); xlabel('X'); ylabel('Y'); 
save poisson_test

function [v] = jacobi(A, v, f, I, T)
%% Jacobi iteration:
% Av = (D+T)v = f
% Dv = f-Tv = (f - Av) + Dv
% v' = v + D^{-1} (f - Av)
d = diag(A);
r = zeros(size(v));
dv = zeros(size(v));
for t = 1:T
    Av = A*v(:); % Apply A on v.
    r(I) = f(I) - Av(I); % Compute residual.
    dv(I) = r(I) ./ d(I); % Compute an update.
    v(I) = v(I) + dv(I); % Update v's interior.
end

function [U, L] = create_sol()
%% Create solutions for the specific diff. eq. instance.
% - F is the function itself (for boundary conditions).
% - L is the Laplacian of F.
% It may be useful for solver's verification.
U = @(X, Y) 0*X+10;
L = @(X, Y) 0*X;

function [X, Y] = create_grid(x, y)
%% Create a grid specified by {X(k), Y(k)}.
% X, Y, I are 2D arrays, created by NDGRID, 
% so X is the 1st coordinate and Y is the 2nd!
[X, Y] = ndgrid(x, y);

function [A, I] = create_laplacian(X, Y, sz)
%% Laplacian discretization using sparse matrix
N = prod(sz);
A = sparse(N, N);
K = true(sz);
if sz(1) > 1, K(1, :) = false; K(end, :) = false; end
if sz(2) > 1, K(:, 1) = false; K(:, end) = false; end
K = find(K); % Fill only interior points
stencil = [-1  0 0 0 1; ...
            0 -1 0 1 0];
stencil_size = size(stencil, 2);
for k = K(:).'
    [i, j] = ind2sub(sz, k);
    i = i + stencil(1, :).';
    j = j + stencil(2, :).';
    m = sub2ind(sz, i, j);
    x = X(m);
    y = Y(m);    
    P = [ones(stencil_size, 1), x, y, x.*y, x.^2, y.^2] \ eye(stencil_size);
    P = sum(P(end-1:end, :));
    A(k, m) = P;
end
I = any(A, 2); % Find out interior points

