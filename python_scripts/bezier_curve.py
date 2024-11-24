import sympy as sy


class BezierCurve:
    def __init__(self, control_points):
        for i, point in enumerate(control_points):
            if len(point) != 2:
                raise ValueError(
                    f"Control point {i} must be a 2D point, but got {point}")
            control_points[i] = sy.Matrix(point)
        self.control_points = control_points
        self.degree = len(control_points) - 1
        self.t = sy.symbols('t')

        self.expr = sy.Matrix([0, 0])
        for i, point in enumerate(control_points):
            self.expr += sy.binomial(self.degree, i) * \
                (1 - self.t)**(self.degree - i) * self.t**i * point

    def get_callable(self):
        return sy.lambdify(self.t, self.expr)


def newton_raphson(f, t):
    p0 = sy.Matrix(sy.var('x_0 y_0'))
    diff = f - p0
    df = f.diff(t)
    F = df.dot(diff)
    return F / F.diff(t), p0


def make_control_point(i):
    u = sy.var(f'u_{i}')
    v = sy.var(f'v_{i}')
    return sy.Matrix([u, v])
