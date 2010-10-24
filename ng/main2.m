function main2(x)

clc;
betas = linspace(1e-4, 1e-3, 1);
gamma = exp(x);
Rinf = 100;

U = zeros(size(betas));
calc_force = @(beta, V) ...
    main1('results', 1, beta, gamma, V, Rinf, ...
    [60 15], 2000);

V_theory = betas * 2*log((gamma^0.25 + gamma^-0.25) / (2*gamma^0.25));

for k = 1:numel(betas)
    Vinf = V_theory(k);
    Vinf = Vinf * linspace(0.9, 1.1, 2);

    F = zeros(size(Vinf));
    for i = 1:numel(Vinf)
        F(i) = calc_force(betas(k), Vinf(i));
    end

    [a0, b0, e, R] = linreg(F(:), Vinf(:));
    U(k) = b0;
    calc_force(betas(k), U(k));
end

fprintf('Errors:\n');
fprintf(' %.2f%%', 100 * (U - V_theory) ./ V_theory);
fprintf('\n');

f = sprintf('gamma[%d]', x);
save(f);