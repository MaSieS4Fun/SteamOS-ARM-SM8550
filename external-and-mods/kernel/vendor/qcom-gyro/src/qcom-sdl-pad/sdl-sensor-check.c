/* Minimal SDL2 check: DualSense reports accel+gyro → Cemu Use motion can enable. */
#include <SDL.h>
#include <stdio.h>
#include <string.h>

int
main(void)
{
	int i, n, found = 0;

	if (SDL_Init(SDL_INIT_GAMECONTROLLER | SDL_INIT_SENSOR) != 0) {
		fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
		return 1;
	}
	n = SDL_NumJoysticks();
	printf("joysticks=%d\n", n);
	for (i = 0; i < n; i++) {
		const char *name = SDL_JoystickNameForIndex(i);
		SDL_bool is_gc = SDL_IsGameController(i);
		printf("[%d] %s gamecontroller=%s\n", i, name ? name : "?",
		       is_gc ? "yes" : "no");
		if (!is_gc)
			continue;
		SDL_GameController *gc = SDL_GameControllerOpen(i);
		if (!gc)
			continue;
		SDL_bool accel = SDL_GameControllerHasSensor(gc, SDL_SENSOR_ACCEL);
		SDL_bool gyro = SDL_GameControllerHasSensor(gc, SDL_SENSOR_GYRO);
		printf("     accel=%s gyro=%s → Use motion %s\n",
		       accel ? "yes" : "no", gyro ? "yes" : "no",
		       (accel && gyro) ? "ENABLED" : "greyed");
		if (accel && gyro && name && strstr(name, "DualSense"))
			found = 1;
		SDL_GameControllerClose(gc);
	}
	SDL_Quit();
	if (!found) {
		fprintf(stderr, "No DualSense with accel+gyro\n");
		return 2;
	}
	printf("PASS: DualSense has SDL sensors (Cemu Use motion should unlock)\n");
	return 0;
}
