g = logspace(0, 1, 1000);

B1 = 2*log(1./(2*g.^(1/2)) + 1/2);
B3 = (31./(320*(g.^(1/2) + 1)) - 9./(320*(g.^(1/2) + 1).^2) + 1/1680);

% 0 = b.^3*(B3 - B1*11/320) + b*B1;
b = sqrt(1./(11/320 - B3./B1));
plot(g, b);
xlabel('\gamma')
ylabel('\beta_c')

