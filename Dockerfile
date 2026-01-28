# Nginx Gateway Dockerfile for Sea-Saw CRM
# This builds a gateway image that serves both frontend and proxies backend

FROM nginx:alpine

# Remove default nginx configuration
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/

# Create directory for frontend static files
# Frontend files will be mounted as a volume from the frontend container
RUN mkdir -p /usr/share/nginx/html

# Set proper permissions
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

# Expose HTTP port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=10s \
    CMD wget --quiet --tries=1 --spider http://localhost/health/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
