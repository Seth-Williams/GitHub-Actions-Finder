# GitHub-Actions-Finder

A command-line tool for discovering and analyzing GitHub Actions usage across repositories and organizations. This tool helps DevOps teams, security professionals, and engineering managers gain insights into their GitHub Actions dependencies.

🔍 Features

Scan any repository or entire organization for GitHub Actions usage
Generate detailed reports in multiple formats (Markdown, Text, HTML)
Categorize actions into different types (GitHub Official, Third-party, Local Repository, Docker)
Identify the most frequently used actions across your workflows
Map actions to workflows to understand where specific actions are used
Get organization-wide insights for better governance and standardization

📋 Requirements

- Bash shell environment
- GitHub CLI installed and authenticated
- Appropriate GitHub permissions to access the repositories you want to analyze

🚀 Installation

Clone this repository:
```bash
git clone https://github.com/your-username/github-actions-finder.git

cd github-actions-finder
```

Make the script executable:
```bash
chmod +x gh-actions-finder.sh
```


💻 Usage

Scanning a Single Repository
```bash
./gh-actions-finder.sh owner/repo [output_format] [output_base_name]
#example
./gh-actions-finder.sh kubernetes/kubernetes md k8s-report
```
Scanning an Organization
```bash
./gh-actions-finder.sh --org organization_name [output_format] [output_base_name]
#example
./gh-actions-finder.sh --org microsoft all ms-actions-report
```

Output Formats

- md - Markdown format (default)
- txt - Plain text format
- html - HTML format with styling
- all - Generate reports in all formats

![image](https://github.com/user-attachments/assets/9ab890b2-16e6-4e94-a996-98ea631840b4)

![image](https://github.com/user-attachments/assets/a38924c3-2603-4e88-b8d2-4b67ad37e9f2)

