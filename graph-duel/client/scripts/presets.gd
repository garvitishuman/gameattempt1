extends RefCounted
# Subject-specific curve packs. x runs -10..10, the plane shows y in -10..10.

const SUBJECTS := [
	{"name": "Mathematics", "curves": [
		["Sine wave", "4*sin(x)"],
		["Parabola", "0.15*x^2-5"],
		["Cubic", "0.02*x^3-x"],
		["Reciprocal", "5/x"],
		["Absolute V", "abs(x)-6"],
		["Tangent", "2*tan(0.5*x)"],
	]},
	{"name": "Physics", "curves": [
		["Projectile arc", "8-0.2*(x-1)^2"],
		["Spring (SHM)", "5*cos(1.5*x)"],
		["Damped oscillation", "8*exp(-0.2*(x+10))*cos(2*x)"],
		["Inverse square", "20/(x^2+2)-4"],
		["v = u + at", "0.8*x+1"],
	]},
	{"name": "Chemistry", "curves": [
		["Radioactive decay", "9*exp(-0.3*(x+10))"],
		["Titration S-curve", "10/(1+exp(-1.2*x))-5"],
		["Boyle's law", "30/(x+11)"],
		["Reaction rate", "0.4*exp(0.35*x)-5"],
	]},
	{"name": "Economics", "curves": [
		["Diminishing returns", "5*ln(x+11)-8"],
		["Exponential growth", "0.5*exp(0.3*x)-3"],
		["Profit parabola", "6-0.1*x^2"],
		["Square-root gain", "4*sqrt(x+10)-8"],
	]},
	{"name": "Biology", "curves": [
		["Logistic growth", "8/(1+exp(-0.7*x))-4"],
		["Bell curve", "8*exp(-0.25*x^2)-3"],
		["Predator-prey", "3*sin(0.8*x)+2*cos(0.4*x)"],
		["Michaelis-Menten", "9*(x+10)/(x+14)-5"],
	]},
	{"name": "Engineering / CS", "curves": [
		["Sawtooth", "(x-floor(x))*8-4"],
		["Square-ish wave", "4*tanh(5*sin(x))"],
		["Log growth", "3*log(x+10.5)*3-6"],
		["Beat pattern", "3*sin(x)*cos(0.3*x)+2*sin(2*x)"],
	]},
]
