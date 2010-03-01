function [v, residuals] = iterate(v, C, d, iters, type)
% Apply an iterative scheme to solve v' = Cv + d.

if nargin < 4
    type = ''; % Use plain Jacobi iteration.
end

% Keep the original size and convert to column vector:
sz = size(v); 
v = v(:);
residuals = zeros(iters, 1);
if strcmpi(type, 'redblack')
    % Prepare Checkerboard pattern
    P = cumsum(ones(sz), 1) + cumsum(ones(sz), 2);
    P = logical(mod(P(:), 2)); 
    % Create logical index Red and Black matrices
    red = P;
    black = ~P;
    % Split {C,d} into their red and black version:
    C_red = C(red, :);
    d_red = d(red, :);    
    C_black = C(black, :);
    d_black = d(black, :);
    % Iterate:
    for iter = 1:iters
        v_old = v;
        v(red) = C_red * v + d_red; % Update v's red interior.
        v(black) = C_black * v + d_black; % Update v's black interior.
        residuals(iter) = norm(v - v_old);        
    end
else
    for iter = 1:iters
        v_old = v;
        v = C * v + d; % Update v's interior.
        residuals(iter) = norm(v - v_old);        
    end
end
v = reshape(v, sz);