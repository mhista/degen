# NGROK Setup for DegenBot

To handle Telegram webhooks locally, you need a public HTTPS URL. Ngrok provides this by creating a secure tunnel to your local machine.

## Prerequisites

1.  **Create an Ngrok Account:** Sign up at [ngrok.com](https://ngrok.com/).
2.  **Install Ngrok CLI:** Follow the instructions on their website to install it on your OS.
3.  **Get Auth Token:** Copy your auth token from the [Ngrok Dashboard](https://dashboard.ngrok.com/get-started/your-authtoken).

## Configuration

1.  **Add Auth Token to `.env`:**
    ```env
    NGROK_AUTH_TOKEN=your_auth_token_here
    ```

2.  **Run Ngrok:**
    Open a terminal and run:
    ```bash
    ngrok http 8080
    ```
    (Replace `8080` with your `SERVER_PORT` if different).

3.  **Update `WEBHOOK_BASE_URL`:**
    Copy the `Forwarding` URL provided by ngrok (it looks like `https://xxxx-xxxx.ngrok-free.app`) and add it to your `.env`:
    ```env
    WEBHOOK_BASE_URL=https://xxxx-xxxx.ngrok-free.app
    ```

4.  **Restart the Server:**
    Run `dart run build_runner build` (to update `env.g.dart`) and then start your server.

## Automatic Setup (Alternative)

If you prefer to start ngrok automatically with your server, you can use the `ngrok` package in Dart (not currently implemented in this project, but an option for future).

## Troubleshooting

- **404 Not Found:** Ensure your Serverpod server is running on the correct port and that the `/telegram` route is registered.
- **Webhook Not Updating:** Telegram sometimes caches old webhook URLs. The `TelegramService` in this project automatically deletes and re-sets the webhook on startup to prevent this.
- **Wait for DNS:** Sometimes it takes a few seconds for the ngrok URL to become active.
