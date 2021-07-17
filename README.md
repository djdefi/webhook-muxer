# Webhook muxer

This is a simple proof of concept that allows you to forward incoming webhooks to any number of URLs.


# Installation

```bash
bundle install
```

# Usage

1. Create a file called `urls.txt` with one url per line.
2. Run the server:
   ```bash
   ruby webhook-muxer.rb
   ```
3. Send a webhook to the server:
   ```bash
   curl -X POST -d '{"foo": "bar"}' http://localhost:4567/
   ```
4. The server will forward the webhook payload to all urls in `urls.txt`.

## Async delivery

An async delivery option is also available.
   
   ```bash
   curl -X POST -d '{"foo": "bar"}' http://localhost:4567/async
   ```

The server will return a 200 status code immediately, and then deliver the webhook payload to all urls in `urls.txt` asynchronously. Any errors in forwarding will not be reported in the response.