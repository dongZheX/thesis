function test1_
tic;
sz = [90 50];
g = Grid(logspace(0, 1, sz(1)), linspace(0, pi, sz(2)));
% variables with boundary conditions
grid.Phi = g.init('central', 'central');
grid.C   = g.init('central', 'central');
grid.Vr  = g.init('', 'central');
grid.Vt  = g.init('central', '');
grid.P   = g.init('interior', 'interior');

% interior grid (ghost points removed)
igrid = noghost(grid);
sol = Solution(igrid, ...
    zeros(igrid.Phi.sz), ...
    ones(igrid.C.sz), ...
    zeros(igrid.Vr.sz), ...
    zeros(igrid.Vt.sz), ...
    zeros(igrid.P.sz));
sol.alpha = 0;
sol.beta = 0.1;
sol.gamma = 10;
sol.Vinf = 0.1;

[bnd] = boundary(grid, sol);
equations(bnd);
% [eqn] = equations(bnd);
% dx = eqn.grad() \ eqn.res();
% sol.step(-dx);
end

function sol = boundary(grid, sol)
    Phi = Interp(grid.Phi, sol.Phi);
    C = Interp(grid.C, sol.C);
    Vr = Interp(grid.Vr, sol.Vr);
    Vt = Interp(grid.Vt, sol.Vt);
    P = Interp(grid.P, sol.P);

    dr = diff(grid.Phi.r(end-1:end));
    dPhi = @(r, t) -dr * sol.beta * cos(t);
    
    c1     = Interp(Grid(sol.C.grid.r(1), sol.C.grid.t), sol.C);
    phi1   = Interp(Grid(sol.Phi.grid.r(1), sol.Phi.grid.t), sol.Phi);
    c0     = Boundary(C,   [-1 0], Func(phi1, 'exp(-phi)'));
    phi0   = Boundary(Phi, [-1 0], Func(c1, '-log(c)'));
    
    cInf   = Boundary(C,   [+1 0], 1);
    phiInf = Interp(Grid(sol.Phi.grid.r(end), sol.Phi.grid.t), sol.Phi);
    phiInf = Boundary(Phi, [+1 0], phiInf + dPhi);

    VrInf  = Boundary(Vr, [+1 0], @(r,t)-sol.Vinf*cos(t));
    VtInf  = Boundary(Vt, [+1 0], @(r,t) sol.Vinf*sin(t));

    sol.Phi = Symm(Phi + phi0 + phiInf);
    sol.C = Symm(C + c0 + cInf);
    
    g = Grid(1, sol.Vt.grid.t);
    xi = -Interp(g, sol.Phi) - log(sol.gamma);
    
    phi   = Interp(Grid(1, sol.Phi.grid.t(2:end-1)), sol.Phi); % Phi at R=1
    Dphi  = Deriv(g, phi, 2); % Dphi/Dtheta at R=1
    Vs    = Func(xi, '4*log((exp(x/2) + 1)/2)') * Dphi;
    Vt1   = Interp(Grid(sol.Vt.grid.r(1), sol.Vt.grid.t), sol.Vt);
    Vt0   = Boundary(Vt, [-1, 0], 2*Vs - Linear(Vs.grid, Vt1) );
    
    sol.Vr = Symm(Vr + VrInf);
    sol.Vt = Vt + Vt0 + VtInf;
    sol.P = P;
end

function op = Boundary(op, dir, val)
    g = op.grid; % result grid
    r = F(g.r, dir(1));
    t = F(g.t, dir(2));
    b = Grid(r, t); % boundary grid
    if ~isa(val, 'Operator')
        val = Const(b, val);
    else
        val = Linear(b, val);
    end
    op = Interp(g, val);
    function x = F(x, d)
        if d > 0, x = x(end); end
        if d < 0, x = x(1); end
        if d == 0, x = x(2:end-1); end
    end
end

function op = Symm(op)
    I = true(op.grid.sz);
    I(:, [1 end]) = false;
    I = find(I);
    
    J1 = false(op.grid.sz);
    J1(:, [1 end]) = true;
    J1 = find(J1); % ghost points
    
    J2 = false(op.grid.sz);    
    J2(:, [2 end-1]) = true;
    J2 = find(J2); % interior points
    
    op = Linear(op.grid, op);
    op.L = sparse([I; J1], [I; J2], 1, op.grid.numel, op.grid.numel);    
end

function flux = charge(sol)
    DPhi_Dr = Crop(Deriv(sol.Vr.grid, sol.Phi, 1), [0 1]);
    DPhi_Dt = Crop(Deriv(sol.Vt.grid, sol.Phi, 2), [1 0]);
    Cr = Interp(DPhi_Dr.grid, sol.C);
    Ct = Interp(DPhi_Dt.grid, sol.C);
    g = sol.Phi.grid;
    g = Grid(g.r(2:end-1), g.t(2:end-1));
    fluxR = Deriv(g, (@(r,t) r^2) * Cr * DPhi_Dr, 1) * @(r,t) r^(-2);
    fluxT = Deriv(g, (@(r,t) sin(t)) * Ct * DPhi_Dt, 2) * @(r,t) 1/(r^2 * sin(t));
    flux = fluxR + fluxT;
end

function flux = salt(sol)
    DC_Dr = Crop(Deriv(sol.Vr.grid, sol.C, 1), [0 1]);
    DC_Dt = Crop(Deriv(sol.Vt.grid, sol.C, 2), [1 0]);
    % XXX Add advection!
    g = sol.Phi.grid;
    g = Grid(g.r(2:end-1), g.t(2:end-1));
    fluxR = Deriv(g, (@(r,t) r^2) * DC_Dr, 1) * @(r,t) r^(-2);
    fluxT = Deriv(g, (@(r,t) sin(t)) * DC_Dt, 2) * @(r,t) 1/(r^2 * sin(t));
    flux = fluxR + fluxT;
end

function equations(sol)
    f = charge(sol); f.res(); f.grad();
%     f = salt(sol); f.res(); f.grad();
    tic;
    f.grad();
    toc;
end

function sol = Solution(grid, varargin)
    sol.grid = grid;
    sol.x = Variable(varargin{:});
    sol.numel = numel(sol.x.value);
    offset = 0;
    F = fieldnames(grid);
    for k = 1:numel(F)
        name = F{k};
        g = grid.(name); % grid for variable
        m = g.numel; % dimension of variable
        op = Linear(g, sol.x); % Linear operator
        op.L = sparse(1:m, offset + (1:m), 1, m, sol.numel); % Restrictor
        sol.(name) = op;
        offset = offset + g.numel;
    end
    function step(dx)
        sol.x.value = sol.x.value + dx;
    end
    sol.step = @step;
end

function grid = noghost(grid)
    for n = fieldnames(grid).'
        g = grid.(n{1}); % remove ghost points from grid
        r = g.r((1+g.ghost(1)):(end-g.ghost(1)));
        t = g.t((1+g.ghost(2)):(end-g.ghost(2)));
        grid.(n{1}) = Grid(r, t);
    end
end
