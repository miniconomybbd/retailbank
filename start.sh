#!/bin/bash
set -e
sudo apt update && sudo apt install -y jq && sudo apt-get install -y unzip && sudo apt install -y openjdk-17-jre-headless


# install aws cli if necessary
if command -v aws &> /dev/null; then
  echo "AWS CLI is already installed at: $(which aws)"

else
  echo "Installing AWS CLI..."
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -o awscliv2.zip
  sudo ./aws/install --update
fi

# clean up crap
rm awscliv2.zip && rm flyway-commandline-10.11.0-linux-x64.tar.gz


# Pull the secrets using the aws cli
aws secretsmanager get-secret-value \
  --secret-id server-cert \
  --query SecretString \
  --output text > /etc/ssl/certs/server.crt

aws secretsmanager get-secret-value \
  --secret-id server-key \
  --query SecretString \
  --output text > /etc/ssl/certs/server.key

aws secretsmanager get-secret-value \
  --secret-id ca-cert \
  --query SecretString \
  --output text > /etc/ssl/certs/client-ca.crt

APP_NAME="RetailBank"
APP_USER="ubuntu"
APP_DIR="/home/ubuntu/build"
EXECUTABLE="$APP_DIR/$APP_NAME"
SERVICE_NAME="retail-bank"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Make the binary executable
echo "Making $EXECUTABLE executable..."
chmod +x "$EXECUTABLE" || { echo "Failed to chmod +x"; exit 1; }

# Create the systemd service file only if it doesn't exist
if [ ! -f "$SERVICE_FILE" ]; then
  echo "Creating systemd service at $SERVICE_FILE..."

  sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=RetailBank API .NET Service
After=network.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$EXECUTABLE
Restart=always
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  echo "Reloading systemd daemon to pick up new service..."
  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
else
  echo "Service file already exists: $SERVICE_FILE"
fi

# restart the service (whether new or updated)
echo "Restarting $SERVICE_NAME service..."
sudo systemctl restart "$SERVICE_NAME"

# show status
echo "Service status:"
sudo systemctl status "$SERVICE_NAME" --no-pager

# setup nginx and https
echo "Setting up nginx and https"

set -e
FE_DOMAIN="retail-bank.pastpaperportal.co.za"
API_DOMAIN="retail-bank-api.pastpaperportal.co.za"

EMAIL="admin@$DOMAIN" 
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NGINX_LINK="/etc/nginx/sites-enabled/$DOMAIN"
FRONTEND_APP_DIR="/home/ubuntu/frontend-build"

echo "Installing nginx and certbot..."
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

echo "Creating temporary HTTP-only nginx config for $FE_DOMAIN..."
sudo tee $NGINX_CONF > /dev/null <<EOF
server {

    listen 80;
    server_name $FE_DOMAIN;

    root $FRONTEND_APP_DIR;
    index index.html;

    location /api/ {
        if ($request_method = GET) {
            proxy_pass http://localhost:5000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Origin \$http_origin;
            proxy_buffering off;
        }
        return 403;
    }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    location ~ /\. {
        deny all;
    }
}

server {
    listen 443 ssl;
    server_name $API_DOMAIN;
    ssl_certificate     /etc/ssl/certs/server.crt;
    ssl_certificate_key /etc/ssl/private/server.key;

    ssl_client_certificate /etc/ssl/certs/client-ca.crt;
    ssl_verify_client on;

    error_log /var/log/nginx/mtls-error.log info;


    location / {
        proxy_pass http://localhost:5000;  # Or your backend
    }
}
EOF

# Setup ssl for the frontend
sudo ln -sf $NGINX_CONF $NGINX_LINK
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d $FE_DOMAIN
sudo systemctl reload nginx




