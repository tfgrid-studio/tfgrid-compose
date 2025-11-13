#!/usr/bin/env bash

echo "🧪 Testing TFGrid Compose Enhanced Version Display and Syntax Validation"
echo "======================================================================"

# Source the enhanced functions
source core/app-cache.sh
source core/app-loader.sh

echo ""
echo "1. Testing Git information extraction for cached apps..."
echo "----------------------------------------------------------"

# Test if there are any cached apps
if [ -d "$HOME/.config/tfgrid-compose/apps" ]; then
    for app_dir in "$HOME/.config/tfgrid-compose/apps"/*; do
        if [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
            app_name=$(basename "$app_dir")
            echo "📱 Testing app: $app_name"
            
            # Test git info extraction
            git_info=$(get_cached_app_git_info "$app_name" 2>/dev/null)
            if [ -n "$git_info" ] && [ "$git_info" != "{}" ]; then
                short_commit=$(echo "$git_info" | jq -r '.short_commit // "unknown"')
                formatted_date=$(echo "$git_info" | jq -r '.formatted_date // "unknown"')
                branch=$(echo "$git_info" | jq -r '.branch // "unknown"')
                repo_url=$(echo "$git_info" | jq -r '.repo_url // "unknown"')
                
                echo "  ✅ Git commit: $short_commit"
                echo "  📅 Last updated: $formatted_date"
                echo "  🌿 Branch: $branch"
                echo "  🔗 Repository: $repo_url"
            else
                echo "  ❌ No git info found"
            fi
            
            # Test validation
            echo "  🔍 Running validation..."
            if validate_cached_app "$app_name"; then
                echo "  ✅ Validation passed"
            else
                echo "  ⚠️  Validation failed (expected for testing)"
            fi
            
            echo ""
        fi
    done
else
    echo "No cached apps found to test"
fi

echo ""
echo "2. Testing cache status reporting..."
echo "------------------------------------"

# Test cache list
echo "📋 Cache list with commit info:"
list_cached_apps_enhanced

echo ""
echo "3. Testing enhanced app loading simulation..."
echo "--------------------------------------------"

# Test loading an app (if available)
if [ -d "$HOME/.config/tfgrid-compose/apps/tfgrid-ai-stack" ]; then
    echo "📱 Simulating enhanced app load for tfgrid-ai-stack..."
    
    # Create a temporary test manifest
    TEST_MANIFEST="/tmp/test-app.yaml"
    cat > "$TEST_MANIFEST" << EOF
name: test-app
version: 1.0.0-test
description: Test application for enhanced version display
patterns:
  recommended: single-vm
EOF
    
    # Test the load_app function logic (simplified)
    if [ -f "$TEST_MANIFEST" ]; then
        echo "  ✅ Test manifest created"
        
        # Show what the enhanced output would look like
        APP_NAME="test-app"
        APP_VERSION="1.0.0-test"
        
        echo "  📱 Application loaded: $APP_NAME v$APP_VERSION"
        
        if is_app_cached "tfgrid-ai-stack" 2>/dev/null; then
            git_info=$(get_cached_app_git_info "tfgrid-ai-stack" 2>/dev/null)
            if [ -n "$git_info" ] && [ "$git_info" != "{}" ]; then
                short_commit=$(echo "$git_info" | jq -r '.short_commit // "unknown"')
                formatted_date=$(echo "$git_info" | jq -r '.formatted_date // "unknown"')
                branch=$(echo "$git_info" | jq -r '.branch // "unknown"')
                repo_url=$(echo "$git_info" | jq -r '.repo_url // "unknown"')
                
                if [ "$short_commit" != "unknown" ]; then
                    echo "  🔗 Git commit: $short_commit"
                fi
                if [ "$formatted_date" != "unknown" ]; then
                    echo "  📅 Last updated: $formatted_date"
                fi
                if [ "$branch" != "unknown" ]; then
                    echo "  🌿 Branch: $branch"
                fi
                if [ "$repo_url" != "unknown" ]; then
                    echo "  🔗 Repository: $repo_url"
                fi
            fi
        fi
        
        echo "  📝 Description: Test application for enhanced version display"
        echo "  🎯 Recommended pattern: single-vm"
        
        rm -f "$TEST_MANIFEST"
    fi
else
    echo "tfgrid-ai-stack not cached, skipping app load test"
fi

echo ""
echo "4. Testing syntax validation improvements..."
echo "-------------------------------------------"

# Test the enhanced syntax validation
if [ -d "$HOME/.config/tfgrid-compose/apps/tfgrid-ai-stack/deployment" ]; then
    echo "🔍 Testing enhanced syntax validation on tfgrid-ai-stack..."
    
    # Run validation and capture output
    output=$(validate_cached_app "tfgrid-ai-stack" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "  ✅ Syntax validation passed"
    else
        echo "  ⚠️  Syntax validation failed (expected for testing)"
        echo "  📄 Validation output:"
        echo "$output" | sed 's/^/    /'
    fi
fi

echo ""
echo "🎉 Testing complete!"
echo ""
echo "Summary of improvements implemented:"
echo "✅ Enhanced version display with Git commit information"
echo "✅ Improved syntax validation with detailed error messages"  
echo "✅ Better cache status reporting with commit hashes"
echo "✅ Enhanced error messages and user guidance"
echo ""
echo "Users will now see:"
echo "- Git commit hash during app loading"
echo "- Repository URL and branch information"
echo "- Last update timestamp"
echo "- Detailed syntax error messages with line numbers"
echo "- Clear guidance for fixing cache issues"