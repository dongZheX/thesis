% Sparse matrix initialization.
% Efficient replacement for repetative usage of sparse() function.
%
% Instead of using "S = sparse(I, J, V, n, m)", each time with different V,
% this function allows to allocate sparse matrix data structure once - 
% and update it inplace (without any reallocation).
%
% Usage example:
%   n = 5; 
%   I = [1:n; 1:n; 1:n]; 
%   J = [1:n; 2:n+1; 3:n+2];
%   mask = spinit(I, J, [n n+2]);
%   for e = [0 1 2]
%       values = repmat([1+e;-2; 1-e], [1 n]);
%       S = mask(values);
%       disp(full(S))
%   end
%
% NOTE: this function supports only real sparse matrices.
function updater = spinit(I, J, sz)

assert( numel(I) == numel(J) );

K = [J(:) I(:) (1:numel(I))'];
K = sortrows(uint32(K)); % Sort non-zero indices by CSR order.
K = K(:, 3); % Used to reorder new values.

% Allocate sparse matrix with specified non-zero pattern.
matrix = sparse(I, J, ones(size(I)), sz(1), sz(2));
clear I J;

% Now it values can be updated inplace using the following function:
function result = update(values)
    result = matrix; % references the allocated matrix.
    values = values(K); % Sort non-zeroes to be in CSC order.
    % NOTE: this MEX code updates previously allocated matrix in-place.
    sparse_update_inplace(result, values);
end

updater = @update;
end
