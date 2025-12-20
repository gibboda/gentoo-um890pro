#!/usr/bin/env bash
#
# cleanup-branches.sh - Script to clean up merged and stale Git branches
#
# This script helps identify and delete branches that have been merged or are no longer needed.
# It will NOT delete the main branch or the current working branch.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
print_info "Current branch: ${CURRENT_BRANCH}"

# Protected branches that should never be deleted
PROTECTED_BRANCHES=("main" "master" "develop" "development")

# Fetch latest from remote (if possible)
print_info "Fetching latest changes from remote..."
if ! git fetch --prune origin 2>/dev/null; then
    print_warning "Could not fetch from remote (authentication may be required)"
    print_info "Continuing with local information..."
fi

# List of merged branches that can be safely deleted
MERGED_BRANCHES=(
    "copilot/configure-snyk-scan-settings"
    "copilot/fix-log-writing-issue"
    "copilot/fix-shellcheck-warning-log-file"
    "copilot/improve-inefficient-code"
    "copilot/improve-code-efficiency"
    "gibboda-patch-3"
    "gibboda-patch-4"
    "gibboda-patch-4-1"
    "gibboda-patch-5"
)

# List of closed/abandoned branches that can be deleted
CLOSED_BRANCHES=(
    "copilot/improve-slow-code-efficiency"
    "gibboda-patch-1"
    "gibboda-patch-2"
)

# Function to check if a branch is protected
is_protected() {
    local branch=$1
    for protected in "${PROTECTED_BRANCHES[@]}"; do
        if [[ "$branch" == "$protected" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to delete local branch
delete_local_branch() {
    local branch=$1
    local force=${2:-false}
    
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        print_info "Deleting local branch: ${branch}"
        if [[ "$force" == "true" ]]; then
            # Force delete for closed branches
            git branch -D "${branch}" 2>/dev/null || print_warning "Local branch ${branch} not found or already deleted"
        else
            # Safe delete for merged branches (will fail if not merged)
            git branch -d "${branch}" 2>/dev/null || print_warning "Local branch ${branch} not merged or already deleted"
        fi
    else
        print_warning "Local branch ${branch} does not exist"
    fi
}

# Function to delete remote branch
delete_remote_branch() {
    local branch=$1
    if git ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1; then
        print_info "Deleting remote branch: origin/${branch}"
        if ! git push origin --delete "${branch}" 2>/dev/null; then
            print_error "Failed to delete remote branch ${branch}. Check network connection and push permissions."
            return 1
        fi
    else
        print_warning "Remote branch ${branch} does not exist or remote is not accessible"
    fi
}

# Main cleanup function
cleanup_branches() {
    local dry_run=${1:-false}
    
    print_info "========================================="
    print_info "Branch Cleanup Summary"
    print_info "========================================="
    
    # Count branches to delete
    local total_count=$((${#MERGED_BRANCHES[@]} + ${#CLOSED_BRANCHES[@]}))
    print_info "Total branches to clean up: ${total_count}"
    print_info "  - Merged branches: ${#MERGED_BRANCHES[@]}"
    print_info "  - Closed branches: ${#CLOSED_BRANCHES[@]}"
    echo ""
    
    if [[ "$dry_run" == "true" ]]; then
        print_warning "DRY RUN MODE - No branches will be deleted"
        echo ""
    fi
    
    # Process merged branches
    print_info "Processing merged branches..."
    for branch in "${MERGED_BRANCHES[@]}"; do
        if is_protected "$branch"; then
            print_warning "Skipping protected branch: ${branch}"
            continue
        fi
        
        if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
            print_warning "Skipping current branch: ${branch}"
            continue
        fi
        
        if [[ "$dry_run" == "true" ]]; then
            print_info "[DRY RUN] Would delete: ${branch}"
        else
            delete_local_branch "$branch" false  # Use safe delete for merged branches
            delete_remote_branch "$branch"
        fi
    done
    
    echo ""
    
    # Process closed branches
    print_info "Processing closed/abandoned branches..."
    for branch in "${CLOSED_BRANCHES[@]}"; do
        if is_protected "$branch"; then
            print_warning "Skipping protected branch: ${branch}"
            continue
        fi
        
        if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
            print_warning "Skipping current branch: ${branch}"
            continue
        fi
        
        if [[ "$dry_run" == "true" ]]; then
            print_info "[DRY RUN] Would delete: ${branch}"
        else
            delete_local_branch "$branch" true  # Force delete for closed branches
            delete_remote_branch "$branch"
        fi
    done
    
    echo ""
    print_info "========================================="
    print_info "Cleanup complete!"
    print_info "========================================="
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --dry-run    Show what would be deleted without actually deleting
    --execute    Execute the branch cleanup
    -h, --help   Show this help message

Examples:
    # Dry run to see what would be deleted
    $0 --dry-run
    
    # Execute the cleanup
    $0 --execute

EOF
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
fi

case "${1:-}" in
    --dry-run)
        cleanup_branches true
        ;;
    --execute)
        print_warning "This will permanently delete branches from both local and remote!"
        read -p "Are you sure you want to continue? (yes/no): " -r
        echo
        if [[ $REPLY =~ ^[Yy]es$ ]]; then
            cleanup_branches false
        else
            print_info "Cleanup cancelled"
            exit 0
        fi
        ;;
    -h|--help)
        show_usage
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
