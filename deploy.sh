#!/bin/bash

# =============================================================================
# Sea-Saw CRM Gateway Deployment Script
# =============================================================================
# This script manages the unified deployment of Sea-Saw CRM
# It orchestrates frontend, backend, and gateway services
#
# Usage:
#   ./deploy.sh [command]
#
# Commands:
#   init          - Initial setup (create config files)
#   pull          - Pull latest images from registry
#   up            - Start all services
#   down          - Stop all services
#   restart       - Restart all services
#   logs          - View logs
#   status        - Check service status
#   backup        - Backup database
#   restore       - Restore database from backup
#   update        - Update services (pull + restart)
#   clean         - Clean old images and volumes
#   help          - Show this help message
# =============================================================================

set -e

# Configuration
COMPOSE_FILE="docker-compose.yml"
COMPOSE_PROJECT_NAME="sea-saw"
DOCKER_REGISTRY="hkccr.ccs.tencentyun.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi

    log_success "All prerequisites met"
}

init_config() {
    log_info "Initializing configuration..."

    if [ ! -d "config" ]; then
        mkdir -p config
    fi

    # Check if config files exist
    if [ ! -f "config/backend.env" ]; then
        if [ -f "config/backend.env.example" ]; then
            cp config/backend.env.example config/backend.env
            log_warning "Created config/backend.env from example. Please edit it with your settings."
        else
            log_error "config/backend.env.example not found"
            exit 1
        fi
    fi

    if [ ! -f "config/postgres.env" ]; then
        if [ -f "config/postgres.env.example" ]; then
            cp config/postgres.env.example config/postgres.env
            log_warning "Created config/postgres.env from example. Please edit it with your settings."
        else
            log_error "config/postgres.env.example not found"
            exit 1
        fi
    fi

    log_success "Configuration initialized"
    log_warning "Please review and update config files before starting services"
}

login_registry() {
    log_info "Logging in to Docker registry..."

    if [ -z "${TCR_USERNAME}" ] || [ -z "${TCR_PASSWORD}" ]; then
        log_warning "TCR_USERNAME or TCR_PASSWORD not set. Skipping registry login."
        log_warning "Set these environment variables or login manually: docker login ${DOCKER_REGISTRY}"
        return
    fi

    echo "${TCR_PASSWORD}" | docker login ${DOCKER_REGISTRY} -u "${TCR_USERNAME}" --password-stdin

    log_success "Logged in to registry"
}

pull_images() {
    log_info "Pulling latest images from registry..."

    login_registry

    docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" pull

    log_success "Images pulled successfully"
}

start_services() {
    log_info "Starting all services..."

    # Check config files
    if [ ! -f "config/backend.env" ] || [ ! -f "config/postgres.env" ]; then
        log_error "Configuration files not found. Run './deploy.sh init' first."
        exit 1
    fi

    docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" up -d

    log_info "Waiting for services to be healthy..."
    sleep 30

    log_success "All services started"
}

stop_services() {
    log_info "Stopping all services..."

    docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" down

    log_success "All services stopped"
}

restart_services() {
    log_info "Restarting all services..."

    stop_services
    sleep 5
    start_services

    log_success "All services restarted"
}

view_logs() {
    service=${1:-}

    if [ -z "$service" ]; then
        log_info "Showing logs for all services..."
        docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" logs -f
    else
        log_info "Showing logs for $service..."
        docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" logs -f "$service"
    fi
}

check_status() {
    log_info "Checking service status..."

    docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" ps

    echo ""
    log_info "Checking health..."

    # Check backend API
    if curl -sf http://localhost/health/ > /dev/null; then
        log_success "Backend API is healthy"
    else
        log_error "Backend API is not responding"
    fi

    # Check frontend
    if curl -sf http://localhost/ > /dev/null; then
        log_success "Frontend is accessible"
    else
        log_error "Frontend is not accessible"
    fi

    # Check Flower
    if curl -sf http://localhost:5555/ > /dev/null; then
        log_success "Flower is accessible"
    else
        log_warning "Flower is not accessible"
    fi
}

backup_database() {
    log_info "Backing up database..."

    BACKUP_DIR="backups"
    mkdir -p "$BACKUP_DIR"

    BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).sql.gz"

    docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" exec -T db \
        pg_dump -U sea_saw_prod_user sea_saw_prod | gzip > "$BACKUP_FILE"

    log_success "Database backed up to $BACKUP_FILE"
}

restore_database() {
    log_info "Restoring database..."

    BACKUP_DIR="backups"

    # Find latest backup
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup_*.sql.gz 2>/dev/null | head -1)

    if [ -z "$LATEST_BACKUP" ]; then
        log_error "No backup found in $BACKUP_DIR"
        exit 1
    fi

    log_info "Restoring from $LATEST_BACKUP"

    gunzip -c "$LATEST_BACKUP" | docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" exec -T db \
        psql -U sea_saw_prod_user sea_saw_prod

    log_success "Database restored successfully"
}

update_services() {
    log_info "Updating all services..."

    # Pull latest images
    pull_images

    # Backup before update
    log_info "Creating backup before update..."
    backup_database || log_warning "Backup failed, continuing with update..."

    # Restart services with new images
    restart_services

    # Run migrations
    log_info "Running database migrations..."
    docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" exec backend python manage.py migrate --noinput

    # Collect static files
    log_info "Collecting static files..."
    docker compose -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT_NAME}" exec backend python manage.py collectstatic --noinput

    log_success "Services updated successfully"
}

clean_resources() {
    log_info "Cleaning old Docker resources..."

    # Clean old images
    docker image prune -af --filter "until=72h"

    # Clean unused volumes (be careful!)
    docker volume prune -f

    log_success "Cleanup completed"
}

show_help() {
    cat << EOF
Sea-Saw CRM Gateway Deployment Script

Usage:
    ./deploy.sh [command]

Commands:
    init            Initialize configuration files
    pull            Pull latest images from registry
    up              Start all services
    down            Stop all services
    restart         Restart all services
    logs [service]  View logs (optionally for specific service)
    status          Check service status
    backup          Backup database
    restore         Restore database from latest backup
    update          Update services (pull + backup + restart + migrations)
    clean           Clean old images and volumes
    help            Show this help message

Environment Variables:
    TCR_USERNAME    Tencent Cloud Registry username (for pulling images)
    TCR_PASSWORD    Tencent Cloud Registry password (for pulling images)

Examples:
    # Initial setup
    ./deploy.sh init
    # Edit config/backend.env and config/postgres.env
    ./deploy.sh up

    # Check status
    ./deploy.sh status

    # View backend logs
    ./deploy.sh logs backend

    # Update all services
    ./deploy.sh update

Services:
    - gateway: Unified nginx gateway (frontend + backend proxy)
    - frontend: React Native Web application
    - backend: Django application
    - db: PostgreSQL database
    - redis: Redis cache
    - celery_worker: Celery worker
    - celery_beat: Celery beat scheduler
    - flower: Celery monitoring

Ports:
    - 80: Gateway (frontend + backend API)
    - 5555: Flower (Celery monitoring)

Architecture:
    Internet (80) → Gateway → Frontend (/) + Backend API (/api/)

Documentation:
    See README.md for detailed documentation

EOF
}

# Main script
main() {
    command=${1:-help}

    case "$command" in
        init)
            init_config
            ;;
        pull)
            check_prerequisites
            pull_images
            ;;
        up)
            check_prerequisites
            start_services
            check_status
            ;;
        down)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        logs)
            view_logs "$2"
            ;;
        status)
            check_status
            ;;
        backup)
            backup_database
            ;;
        restore)
            restore_database
            ;;
        update)
            check_prerequisites
            update_services
            ;;
        clean)
            clean_resources
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
