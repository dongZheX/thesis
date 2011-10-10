function [L] = vector_laplacian(F)
    syms r t
    L = [scalar_laplacian(F(1)) ...
         - 2 * F(1) / (r^2) - 2 * diff(sin(t) * F(2), t) / (r^2 * sin(t)); ...
         scalar_laplacian(F(2)) ...
         - F(2) / (r * sin(t))^2 + 2 * diff(F(1), t) / r^2];
end