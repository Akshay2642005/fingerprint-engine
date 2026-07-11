/**
 * Permissions API collector.
 * Queries permission states for various browser APIs.
 */

export interface PermissionStates {
	notifications: string;
	geolocation: string;
	camera: string;
	microphone: string;
}

/**
 * Query permission status for a given API.
 */
async function queryPermission(name: PermissionName): Promise<string> {
	try {
		if (!navigator.permissions) return "unsupported";
		const status = await navigator.permissions.query({ name });
		return status.state; // 'granted', 'denied', or 'prompt'
	} catch {
		return "unsupported";
	}
}

/**
 * Collect permission states for all tracked APIs.
 */
export async function collectPermissions(): Promise<PermissionStates> {
	const [notifications, geolocation, camera, microphone] = await Promise.all([
		queryPermission("notifications" as PermissionName),
		queryPermission("geolocation" as PermissionName),
		queryPermission("camera" as PermissionName),
		queryPermission("microphone" as PermissionName),
	]);

	return { notifications, geolocation, camera, microphone };
}
