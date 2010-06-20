function A = laplacian(interior, X, Y, C)
%% Laplacian discretization using sparse matrix
sz = size(interior);
N = prod(sz);
if nargin < 4
    C = ones(sz); % Assume uniform C
end

ind = @(I, J) sub2ind(sz, I, J);
K = find(interior); % Fill only interior points
K = K(:);
[I, J] = ind2sub(sz, K);
Dp = repmat([1 0 -1], [numel(K) 1]); 
% NOTE: The stencil is constructed as: [forward, middle, backward] coefficients.
Ip = repmat(I, [1 3]);
Jp = repmat(J, [1 3]);
Kp = repmat((1:numel(K))', [1 3]); % interior variables' indices, for 1D Laplacian stencil

% Build 2D sparse matrix L = "Dxx/Mxx" + "Dyy/Myy":

% for X
    Kr = ind(I+1, J); % Left
    Kl = ind(I-1, J); % Right
    Dxx = ... % Laplacian stencil in X direction
     col(( C(Kr) + C(K) ) ./ (( X(Kr) - X(K) ))) * [1 -1 0] -  ...
     col(( C(K) + C(Kl) ) ./ (( X(K) - X(Kl) ))) * [0 1 -1];
    P = ind(Ip + Dp, Jp); % column indices
    Dxx = sparse(Kp, P, Dxx, numel(K), N);
    % The denumerator is separated, for A to be symmetric
    % (since the original operator is self-adjoint).
    Mxx = sparse(1:numel(K), 1:numel(K), (X(Kr) - X(Kl)), numel(K), numel(K));
% Laplacian for X direction is (pinv(Mxx) * Dxx)

% for Y
    Ku = ind(I, J+1); % Up
    Kd = ind(I, J-1); % Down
    Dyy = ... % Laplacian stencil in Y direction
     col(( C(Ku) + C(K) ) ./ (( Y(Ku) - Y(K) ))) * [1 -1 0] -  ...
     col(( C(K) + C(Kd) ) ./ (( Y(K) - Y(Kd) ))) * [0 1 -1];
    P = ind(Ip, Jp + Dp); % column indices
    Dyy = sparse(Kp, P, Dyy, numel(K), N);
    % The denumerator is separated, for A to be symmetric
    % (since the original operator is self-adjoint).
    Myy = sparse(1:numel(K), 1:numel(K), (Y(Ku) - Y(Kd)), numel(K), numel(K));
% Laplacian for Y direction is (pinv(Myy) * Dyy)

% % The actual Laplacian matrix is:
% A = dinv(Mxx) * Dxx + dinv(Myy) * Dyy;

% Pre-multiply it by (Mxx * Myy) for symmetry of A.
M = Mxx * Myy;
L = Myy * Dxx + Mxx * Dyy;
A = dinv(M) * L;