# BrushLoop API and WebSocket

## REST Endpoints

All authenticated endpoints use:

- Header: `Authorization: Bearer <token>`

### Health

- `GET /health`

### Auth

- `POST /api/auth/register`
  - Body: `{ "email": string, "password": string, "displayName": string }`
- `POST /api/auth/login`
  - Body: `{ "email": string, "password": string }`
- `GET /api/auth/me`

### Contacts

- `POST /api/contacts/invite`
  - Body: `{ "inviteeEmail": string }`
- `GET /api/contacts/invitations`
- `POST /api/contacts/invitations/:invitationId/accept`
- `GET /api/contacts`

### Artworks

- `POST /api/artworks`
  - Body includes title, mode, participants, dimensions, optional turn duration.
- `GET /api/artworks`
- `GET /api/artworks/:artworkId`

### Turns

- `POST /api/turns/submit`
  - Body: `{ "artworkId": string }`

## WebSocket Endpoint

- `GET /ws` (upgrade)

### Client Messages

- `client.hello`
- `client.join_artwork`
- `client.leave_artwork`
- `client.request_sync`
- `client.apply_operations`

### Server Messages

- `server.hello_ack`
- `server.snapshot`
- `server.operations`
- `server.presence`
- `server.turn_advanced`
- `server.error`
