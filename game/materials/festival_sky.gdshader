shader_type sky;
uniform float night = 0.0;
float hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float noise2(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y);
}
void sky() {
	vec3 d=EYEDIR;
	float h=clamp(d.y,0.0,1.0);
	vec3 day=mix(vec3(0.67,0.75,0.79),vec3(0.12,0.41,0.59),smoothstep(-0.04,0.7,h));
	vec3 dark=mix(vec3(0.21,0.16,0.28),vec3(0.014,0.027,0.10),smoothstep(-0.03,0.6,h));
	vec3 col=mix(day,dark,night);
	vec2 uv=d.xz/(0.17+h)*2.1;
	float cloud=noise2(uv)*0.59+noise2(uv*2.03)*0.28+noise2(uv*4.07)*0.13;
	col=mix(col,mix(vec3(0.95,0.90,0.80),vec3(0.28,0.25,0.40),night),smoothstep(0.48,0.70,cloud)*0.74);
	float disc=distance(d,normalize(vec3(-0.42,0.32,-0.84)));
	col+=mix(vec3(1.0,0.68,0.28),vec3(0.75,0.83,1.0),night)*(0.23*exp(-8.0*disc)+1.3*(1.0-smoothstep(0.043,0.048,disc)));
	vec2 star=SKY_COORDS*vec2(540,270);
	col+=vec3(0.85,0.86,1.0)*step(0.986,hash(floor(star)))*(1.0-smoothstep(0.05,0.26,length(fract(star)-0.5)))*night*smoothstep(0.0,0.24,h);
	COLOR=col;
}
