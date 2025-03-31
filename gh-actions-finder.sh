#!/bin/bash
# gh-actions-finder.sh - Find all GitHub Actions used in a repository or organization
# Usage: 
#   Single repo:  ./gh-actions-finder.sh <owner/repo> [output_file]
#   Organization: ./gh-actions-finder.sh --org <org> [output_file]

set -e

# Function to show usage
show_usage() {
  echo "Usage:"
  echo "  Single repository: $0 <owner/repo> [output_file]"
  echo "  Organization:      $0 --org <org> [output_file]"
  echo ""
  echo "Examples:"
  echo "  $0 kubernetes/kubernetes actions-report.md"
  echo "  $0 --org microsoft org-actions-report.md"
}

# Check arguments
if [ $# -lt 1 ] || [ $# -gt 3 ]; then
  show_usage
  exit 1
fi

# Determine if we're processing an org or a repo
if [[ "$1" == "--org" ]]; then
  # Organization mode
  if [ $# -lt 2 ]; then
    show_usage
    exit 1
  fi
  ORG_MODE=true
  ORG=$2
  OUTPUT_FILE="${3:-}"  # Use provided output file or empty string
else
  # Repository mode
  ORG_MODE=false
  REPO=$1
  OUTPUT_FILE="${2:-}"  # Use provided output file or empty string
fi

TEMP_DIR=$(mktemp -d)
ACTIONS_FILE="${TEMP_DIR}/actions.txt"

# Function to output to both console and file if output file is specified
output() {
  echo "$1"
  if [ -n "$OUTPUT_FILE" ]; then
    if [[ "$2" != "console_only" ]]; then
      echo "$1" >> "$OUTPUT_FILE"
    fi
  fi
}

# Function to output to file only
file_output() {
  if [ -n "$OUTPUT_FILE" ]; then
    echo "$1" >> "$OUTPUT_FILE"
  fi
}

# Check if gh command is available
if ! command -v gh &> /dev/null; then
  echo "GitHub CLI (gh) is not installed. Please install it first."
  echo "Visit: https://cli.github.com/manual/installation"
  exit 1
fi

# Check if logged in
if ! gh auth status &> /dev/null; then
  echo "You need to log in to GitHub CLI first."
  echo "Run: gh auth login"
  exit 1
fi

# Function to extract actions from a workflow file
extract_actions() {
  local file_content=$1
  local file_path=$2
  local repo_name=$3
  
  # Use grep to find all 'uses:' lines and extract the action name
  echo "$file_content" | grep -E '^\s*uses:' | sed 's/.*uses:\s*\(.*\)$/\1/' | sed 's/^["'"'"']\(.*\)["'"'"']$/\1/' | 
  while read -r ACTION; do
    # Remove any trailing whitespace
    ACTION=$(echo "$ACTION" | xargs)
    if [ -n "$ACTION" ]; then
      if [ -n "$repo_name" ]; then
        echo "$ACTION|$file_path|$repo_name"
      else
        echo "$ACTION|$file_path"
      fi
    fi
  done
}

# Function to process a repository
process_repository() {
  local repo=$1
  local output_file=$2
  local org_mode=$3
  local temp_dir=$4
  local all_actions_file=$5
  
  local repo_actions_file="${temp_dir}/$(echo "$repo" | tr '/' '_')_actions.txt"
  
  output "Finding GitHub Actions in $repo..." "console_only"
  output "--------------------------------" "console_only"

  # List all workflow files in the repository
  output "Searching for workflow files..." "console_only"
  WORKFLOW_FILES=$(gh api "repos/$repo/contents/.github/workflows" --jq '.[].path' 2>/dev/null || echo "")

  # Simple check for error responses or empty results
  if [[ -z "$WORKFLOW_FILES" || "$WORKFLOW_FILES" == *"message"*"Not Found"* || "$WORKFLOW_FILES" == *"message"*"empty"* ]]; then
    output "No workflow files found in $repo repository." "console_only"
    return 0
  fi

  # Display all workflow files to console only
  output "Found workflow files:" "console_only"
  echo "$WORKFLOW_FILES" | sed 's/^/- /' | while read -r LINE; do
    output "$LINE" "console_only"
  done
  output "" "console_only"

  # Process each workflow file
  for FILE_PATH in $WORKFLOW_FILES; do
    # Only process .yml and .yaml files
    if [[ "$FILE_PATH" == *.yml || "$FILE_PATH" == *.yaml ]]; then
      output "Processing $FILE_PATH..." "console_only"
      
      # Get file content
      FILE_CONTENT=$(gh api "repos/$repo/contents/$FILE_PATH" --jq '.content' | base64 --decode 2>/dev/null || echo "")
      
      if [ -n "$FILE_CONTENT" ]; then
        # Extract actions
        if [ "$org_mode" = true ]; then
          extract_actions "$FILE_CONTENT" "$FILE_PATH" "$repo" >> "$repo_actions_file"
        else
          extract_actions "$FILE_CONTENT" "$FILE_PATH" >> "$repo_actions_file"
        fi
      else
        output "  Warning: Could not retrieve content for $FILE_PATH" "console_only"
      fi
    else
      output "Skipping non-workflow file: $FILE_PATH" "console_only"
    fi
  done

  # If we're in org mode, append to the all actions file
  if [ "$org_mode" = true ] && [ -f "$repo_actions_file" ] && [ -s "$repo_actions_file" ]; then
    cat "$repo_actions_file" >> "$all_actions_file"
    return 0
  fi

  # For repo mode, generate the report here
  if [ "$org_mode" = false ]; then
    generate_repo_report "$repo" "$repo_actions_file" "$output_file" "$temp_dir"
  fi
}

# Function to generate a report for a single repository
generate_repo_report() {
  local repo=$1
  local actions_file=$2
  local output_file=$3
  local temp_dir=$4
  
  # Initialize repo output file
  if [ -n "$output_file" ]; then
    echo "# GitHub Actions Report for $repo" > "$output_file"
    echo "Generated on $(date)" >> "$output_file"
    echo "" >> "$output_file"
    echo "## GitHub Actions Found" >> "$output_file"
    echo "" >> "$output_file"
  fi

  output "" "console_only"
  if [ -f "$actions_file" ] && [ -s "$actions_file" ]; then
    output "GitHub Actions Found:" "console_only"
    output "--------------------" "console_only"
    
    # Create a temporary file for unique actions
    UNIQUE_ACTIONS="${temp_dir}/unique_actions.txt"
    GROUPED_ACTIONS="${temp_dir}/grouped_actions.txt"
    
    # Get unique actions first
    cut -d'|' -f1 "$actions_file" | sort | uniq > "$UNIQUE_ACTIONS"
    
    # For each unique action, find all files that use it
    while read -r ACTION; do
      FILES=$(grep "^$ACTION|" "$actions_file" | cut -d'|' -f2 | sort | uniq | tr '\n' ',' | sed 's/,$//')
      OCCURRENCES=$(grep -c "^$ACTION|" "$actions_file")
      echo "$ACTION|$OCCURRENCES|$FILES" >> "$GROUPED_ACTIONS"
    done < "$UNIQUE_ACTIONS"
    
    # Sort by occurrence count (descending)
    sort -t'|' -k2,2nr "$GROUPED_ACTIONS" | while IFS='|' read -r ACTION OCCURRENCES FILES; do
      # Output to console
      output "$ACTION (used $OCCURRENCES times)" "console_only"
      output "  Used in: ${FILES//,/, }" "console_only"
      
      # Categorize the action
      if [[ "$ACTION" == actions/* || "$ACTION" == github/* ]]; then
        CATEGORY="GitHub Official"
      elif [[ "$ACTION" == docker://* ]]; then
        CATEGORY="Docker Image"
      elif [[ "$ACTION" == ./* || "$ACTION" == ../* ]]; then
        CATEGORY="Local Repository"
      elif [[ "$ACTION" == *@* ]]; then
        CATEGORY="Third-party"
      else
        CATEGORY="Other/Composite"
      fi
      output "  Type: $CATEGORY" "console_only"
      output "" "console_only"
      
      # Output to file with markdown formatting
      if [ -n "$output_file" ]; then
        file_output "### $ACTION"
        file_output "- **Used:** $OCCURRENCES times"
        file_output "- **Type:** $CATEGORY"
        file_output "- **Workflows:** ${FILES//,/, }"
        file_output ""
      fi
    done
    
    # Summary statistics
    output "Summary Statistics:" "console_only"
    output "------------------" "console_only"
    TOTAL_ACTIONS=$(wc -l < "$UNIQUE_ACTIONS")
    output "Total unique actions: $TOTAL_ACTIONS" "console_only"
    
    GITHUB_OFFICIAL=$(grep -E '^actions/|^github/' "$actions_file" | cut -d'|' -f1 | sort | uniq | wc -l)
    THIRD_PARTY=$(grep -v -E '^actions/|^github/|^docker://|^\./' "$actions_file" | grep '@' | cut -d'|' -f1 | sort | uniq | wc -l)
    LOCAL_REPO=$(grep -E '^\./' "$actions_file" | cut -d'|' -f1 | sort | uniq | wc -l)
    DOCKER=$(grep '^docker://' "$actions_file" | cut -d'|' -f1 | sort | uniq | wc -l)
    OTHER=$((TOTAL_ACTIONS - GITHUB_OFFICIAL - THIRD_PARTY - LOCAL_REPO - DOCKER))
    
    output "GitHub Official: $GITHUB_OFFICIAL" "console_only"
    output "Third-party: $THIRD_PARTY" "console_only"
    output "Local Repository: $LOCAL_REPO" "console_only" 
    output "Docker Images: $DOCKER" "console_only"
    output "Other/Composite: $OTHER" "console_only"
    
    # Write summary to file in markdown format
    if [ -n "$output_file" ]; then
      file_output "## Summary"
      file_output ""
      file_output "| Category | Count |"
      file_output "|----------|-------|"
      file_output "| GitHub Official | $GITHUB_OFFICIAL |"
      file_output "| Third-party | $THIRD_PARTY |"
      file_output "| Local Repository | $LOCAL_REPO |"
      file_output "| Docker Images | $DOCKER |"
      file_output "| Other/Composite | $OTHER |"
      file_output "| **Total** | **$TOTAL_ACTIONS** |"
    fi
  else
    output "No GitHub Actions found in workflow files." "console_only"
    if [ -n "$output_file" ]; then
      file_output "No GitHub Actions found in workflow files."
    fi
  fi
}

# Function to generate a report for an organization
generate_org_report() {
  local org=$1
  local all_actions_file=$2
  local output_file=$3
  local temp_dir=$4
  
  # Initialize org output file
  if [ -n "$output_file" ]; then
    echo "# GitHub Actions Report for $org Organization" > "$output_file"
    echo "Generated on $(date)" >> "$output_file"
    echo "" >> "$output_file"
  fi
  
  if [ -f "$all_actions_file" ] && [ -s "$all_actions_file" ]; then
    echo "Generating organization-wide report..."
    
    # Create a summary section for the organization
    if [ -n "$output_file" ]; then
      file_output "## Organization-wide Actions Summary"
      file_output ""
      
      # Table of actions and their usage across repos
      file_output "### GitHub Actions Used Throughout Org"
      file_output ""
      file_output "| Action | Used in # Repos | Repositories |"
      file_output "|--------|----------------|--------------|"
      
      # For each unique action, find all repos that use it
      cut -d'|' -f1,3 "$all_actions_file" | sort | uniq | 
      awk -F'|' '{
        actions[$1]++;
        if (!repos[$1]) repos[$1] = $2;
        else if (!index(repos[$1], $2)) repos[$1] = repos[$1] ", " $2;
      }
      END {
        for (action in actions) {
          print action "|" actions[action] "|" repos[action];
        }
      }' | sort -t'|' -k2,2nr | while IFS='|' read -r ACTION REPO_COUNT REPO_LIST; do
        # Categorize the action
        if [[ "$ACTION" == actions/* || "$ACTION" == github/* ]]; then
          CATEGORY="GitHub Official"
        elif [[ "$ACTION" == docker://* ]]; then
          CATEGORY="Docker Image"
        elif [[ "$ACTION" == ./* || "$ACTION" == ../* ]]; then
          CATEGORY="Local Repository"
        elif [[ "$ACTION" == *@* ]]; then
          CATEGORY="Third-party"
        else
          CATEGORY="Other/Composite"
        fi
        
        file_output "| $ACTION | $REPO_COUNT | $REPO_LIST |"
      done
      
      file_output ""
      
      # Summary of repositories with action counts
      file_output "### Repositories Summary"
      file_output ""
      file_output "| Repository | Actions Count |"
      file_output "|------------|---------------|"
      
      # Count unique actions per repo
      cut -d'|' -f1,3 "$all_actions_file" | sort | uniq | 
      awk -F'|' '{
        repos[$2]++;
      }
      END {
        for (repo in repos) {
          print repo "|" repos[repo];
        }
      }' | sort -t'|' -k2,2nr | while IFS='|' read -r REPO ACTION_COUNT; do
        file_output "| $REPO | $ACTION_COUNT |"
      done
      
      file_output ""
      file_output "---"
      file_output ""
    fi
    
    # Add repository details sections
    if [ -n "$output_file" ]; then
      echo "Adding individual repository details..."
      
      # Get unique repositories
      cut -d'|' -f3 "$all_actions_file" | sort | uniq | while read -r REPO; do
        # Create a temporary file for this repo's actions
        REPO_ACTIONS_FILE="${temp_dir}/$(echo "$REPO" | tr '/' '_')_only.txt"
        
        # Extract actions for this repo
        grep "|$REPO$" "$all_actions_file" > "$REPO_ACTIONS_FILE"
        
        # Create a header for this repository
        REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
        file_output "## Repository: $REPO_NAME"
        file_output ""
        
        # Process the repository's actions
        UNIQUE_ACTIONS="${temp_dir}/$(echo "$REPO" | tr '/' '_')_unique.txt"
        GROUPED_ACTIONS="${temp_dir}/$(echo "$REPO" | tr '/' '_')_grouped.txt"
        
        # Get unique actions for this repo
        cut -d'|' -f1 "$REPO_ACTIONS_FILE" | sort | uniq > "$UNIQUE_ACTIONS"
        
        # For each unique action, find all files that use it
        while read -r ACTION; do
          FILES=$(grep "^$ACTION|" "$REPO_ACTIONS_FILE" | cut -d'|' -f2 | sort | uniq | tr '\n' ',' | sed 's/,$//')
          OCCURRENCES=$(grep -c "^$ACTION|" "$REPO_ACTIONS_FILE")
          echo "$ACTION|$OCCURRENCES|$FILES" >> "$GROUPED_ACTIONS"
        done < "$UNIQUE_ACTIONS"
        
        # Output actions for this repository
        sort -t'|' -k2,2nr "$GROUPED_ACTIONS" | while IFS='|' read -r ACTION OCCURRENCES FILES; do
          # Categorize the action
          if [[ "$ACTION" == actions/* || "$ACTION" == github/* ]]; then
            CATEGORY="GitHub Official"
          elif [[ "$ACTION" == docker://* ]]; then
            CATEGORY="Docker Image"
          elif [[ "$ACTION" == ./* || "$ACTION" == ../* ]]; then
            CATEGORY="Local Repository"
          elif [[ "$ACTION" == *@* ]]; then
            CATEGORY="Third-party"
          else
            CATEGORY="Other/Composite"
          fi
          
          file_output "### $ACTION"
          file_output "- **Used:** $OCCURRENCES times"
          file_output "- **Type:** $CATEGORY"
          file_output "- **Workflows:** ${FILES//,/, }"
          file_output ""
        done
        
        # Repository summary statistics
        TOTAL_ACTIONS=$(wc -l < "$UNIQUE_ACTIONS")
        
        GITHUB_OFFICIAL=$(grep -E '^actions/|^github/' "$REPO_ACTIONS_FILE" | cut -d'|' -f1 | sort | uniq | wc -l)
        THIRD_PARTY=$(grep -v -E '^actions/|^github/|^docker://|^\./' "$REPO_ACTIONS_FILE" | grep '@' | cut -d'|' -f1 | sort | uniq | wc -l)
        LOCAL_REPO=$(grep -E '^\./' "$REPO_ACTIONS_FILE" | cut -d'|' -f1 | sort | uniq | wc -l)
        DOCKER=$(grep '^docker://' "$REPO_ACTIONS_FILE" | cut -d'|' -f1 | sort | uniq | wc -l)
        OTHER=$((TOTAL_ACTIONS - GITHUB_OFFICIAL - THIRD_PARTY - LOCAL_REPO - DOCKER))
        
        file_output "#### Repository Summary"
        file_output ""
        file_output "| Category | Count |"
        file_output "|----------|-------|"
        file_output "| GitHub Official | $GITHUB_OFFICIAL |"
        file_output "| Third-party | $THIRD_PARTY |"
        file_output "| Local Repository | $LOCAL_REPO |"
        file_output "| Docker Images | $DOCKER |"
        file_output "| Other/Composite | $OTHER |"
        file_output "| **Total** | **$TOTAL_ACTIONS** |"
        
        file_output ""
        file_output "---"
        file_output ""
      done
    fi
  else
    echo "No GitHub Actions found in any repository."
    if [ -n "$output_file" ]; then
      file_output "No GitHub Actions found in any repository."
    fi
  fi
}

# Main processing logic
if [ "$ORG_MODE" = true ]; then
  # Organization mode
  echo "Analyzing GitHub Actions across $ORG organization..."
  
  # Initialize output file for organization
  if [ -n "$OUTPUT_FILE" ]; then
    echo "# GitHub Actions Report for $ORG Organization" > "$OUTPUT_FILE"
    echo "Generated on $(date)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
  fi
  
  # Find all repositories in the organization
  echo "Finding repositories in $ORG organization..."
  REPOS=$(gh repo list "$ORG" --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner')
  
  if [ -z "$REPOS" ]; then
    echo "No repositories found in $ORG organization."
    exit 0
  fi
  
  REPO_COUNT=$(echo "$REPOS" | wc -l)
  echo "Found $REPO_COUNT repositories."
  echo ""
  
  # Create a file for all actions across the organization
  ALL_ACTIONS_FILE="${TEMP_DIR}/all_actions.txt"
  touch "$ALL_ACTIONS_FILE"
  
  # Initialize counter
  CURRENT_REPO=0
  
  # Process each repository
  for REPO in $REPOS; do
    CURRENT_REPO=$((CURRENT_REPO + 1))
    echo "[$CURRENT_REPO/$REPO_COUNT] Processing $REPO..."
    
    # Process this repository
    process_repository "$REPO" "" true "$TEMP_DIR" "$ALL_ACTIONS_FILE" || {
      echo "  Warning: Failed to process $REPO"
      continue
    }
  done
  
  # Generate the organization report
  generate_org_report "$ORG" "$ALL_ACTIONS_FILE" "$OUTPUT_FILE" "$TEMP_DIR"
else
  # Single repository mode
  process_repository "$REPO" "$OUTPUT_FILE" false "$TEMP_DIR" ""
fi

# Clean up
rm -rf "$TEMP_DIR"
echo "Done!"

# Inform the user about the output file
if [ -n "$OUTPUT_FILE" ]; then
  echo ""
  echo "Results saved to: $OUTPUT_FILE"
fi
