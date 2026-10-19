# Graph Duel — multiplayer-ready export

This project has two parts: the Godot client (`client/`) and a separate authoritative multiplayer server (`server/`). **Exporting the Godot client alone does not host a multiplayer game.** All players must connect to the same publicly reachable server.

## Deploy the multiplayer server (one-time setup)

The included `render.yaml` is a Render Blueprint configuration.

1. Upload/push this `graph-duel` folder to a Git repository.
2. In Render, create a new **Blueprint** from that repository and deploy the `render.yaml` service.
3. Wait for deployment to finish. Render will provide an HTTPS address such as `https://your-service.onrender.com`.
4. In the game menu, enter the matching WebSocket address (the Server field is intentionally blank until configured): `wss://your-service.onrender.com` (replace with your actual host). Do not use `localhost` for people playing on other computers.
5. Create a room, then have every other player enter the exact same `wss://` address and join with the room name and password. Invite links include the server address.

If room creation fails, first open your Render service URL in a browser; it should display `Graph Duel server OK`. If it does not, the server is not deployed/healthy yet. Then enter the matching `wss://` URL in the game. The server uses Render's assigned `PORT` environment variable and exposes `/` as a health check. On other Node.js hosts, run `cd server && npm start`; set `PORT` if the host requires it. Use a host that supports WebSocket upgrades and TLS for `wss://`.

## Run locally

- Install Node.js 18 or newer.
- Start the server: `cd server && npm start`
- Open `client/project.godot` in Godot 4.3+ and run/export the project.
- On the same computer, use `ws://localhost:8080`. For LAN play, use `ws://<host-LAN-IP>:8080` and allow inbound TCP port 8080 through the host firewall.
- For internet play, deploy the server and use its `wss://` address.

## Export checklist

- Export the client from Godot as usual.
- Keep the server deployed and running independently; the server is not embedded in the client export.
- Ensure all players use the same server URL, room name, and password.
- Use `wss://` for public internet hosting. `ws://localhost:8080` only points to the local device and will not work as a shared internet server.
- If a hosted service sleeps while idle, the first connection may take a little longer.

## Tests

Run `cd server && npm test`. The server is authoritative: it stores hidden positions and curves, validates actions, and resolves damage.
