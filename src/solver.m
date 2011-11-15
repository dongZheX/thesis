% load
% v = []; for k = 1:numel(solutions), v(k) = solutions{k}.Vinf; end
% b = []; for k = 1:numel(solutions), b(k) = solutions{k}.beta; end
% loglog(b, v)
function solver
    tic;
    clc;
    filename = datestr(now, 'YYYYmmmdd-HHMMSS');
    sol = struct( ...
        'radius', logspace(0, 7, 400), ...
        'theta', linspace(0, pi, 50), ...
        'gamma', 1-.001, ...
        'alpha', 0, ...
        'maxres', 1e-11, ...
        'iters', [2 5] ...    
    );
    betas = 10.^([-3:0.1:0]);
    sol = force(sol); % initialize force solver
    sol.Vinf = 0.1;
    solutions = cell(numel(betas), 1);
    for k = 1:numel(betas)
        sol.beta = betas(k);
        alphas = [0]; % XXX
        for a = alphas
            sol.alpha = a;
            [sol, V, F] = steady(sol, sol.Vinf*(1+[-0.1, 0.1]), 5);
        end
        solutions{k} = sol;
        pause(0);
        pynotify('CEK', sprintf('%.1f%% completed.', 100*k/numel(betas)));
    end
    v = []; for k = 1:numel(solutions), v(k) = solutions{k}.Vinf; end
    
    g = sol.gamma;
    B3 = (31/(320*(g^(1/2) + 1)) - 9/(320*(g^(1/2) + 1)^2) + 1/1680);
    B1 = 2*log(1/(2*g^(1/2)) + 1/2);
    b = logspace(-3, 0, 1000);
    w = b.^3*(B3 - B1*11/320) + b*B1;
    clf;
    graph = @(x, y, s) plot(log10(x(y>0)), log10(y(y>0)), ['b' s], ...
                         log10(x(y<=0)), log10(-y(y<=0)), ['r' s]);
    hold on
    graph(betas, v, '.');
    graph(b, w, '-');
    hold off
    title(sprintf('\\gamma = %.3e\na = %.2f', sol.gamma, sol.alpha))
    print('-dpng', filename)
    logger('solver', 'Saving results to %s', filename);
    save(filename)
end
