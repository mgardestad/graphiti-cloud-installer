# Contributing to Graphiti Cloud Installer

Thank you for your interest in contributing to Graphiti Cloud Installer! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Submitting Changes](#submitting-changes)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)

## Code of Conduct

This project adheres to a code of conduct that all contributors are expected to follow:

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive feedback
- Assume good intentions
- Respect differing viewpoints and experiences

## How Can I Contribute?

### Reporting Bugs

If you find a bug, please create an issue using the bug report template. Include:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs actual behavior
- Your environment (OS, cloud platform, versions)
- Relevant logs or error messages
- Screenshots if applicable

### Suggesting Enhancements

We welcome feature requests and enhancement suggestions! Please:

- Use the feature request template
- Provide a clear use case
- Explain why this enhancement would be useful
- Consider implementation complexity

### Contributing Code

1. **Fork the repository** and create a branch from `main`
2. **Make your changes** following our coding standards
3. **Test thoroughly** on at least one platform
4. **Update documentation** if needed
5. **Submit a pull request** using our PR template

## Development Setup

### Prerequisites

- Bash 4.0 or higher
- Git
- Access to at least one cloud platform (GCP, AWS, or Azure) for testing
- Docker and Docker Compose (for local testing)

### Local Development

1. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/graphiti-cloud-installer.git
   cd graphiti-cloud-installer
   ```

2. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. Make your changes and test locally

4. Run validation scripts:
   ```bash
   # Test utility functions
   bash test/test_utils.sh
   
   # Test error handling
   bash test/test_error_handling.sh
   ```

## Coding Standards

### Bash Script Guidelines

1. **Use shellcheck** to validate your scripts:
   ```bash
   shellcheck install-*.sh common/*.sh
   ```

2. **Follow these conventions**:
   - Use `#!/bin/bash` shebang
   - Enable strict mode: `set -euo pipefail`
   - Use meaningful variable names in lowercase with underscores
   - Use UPPERCASE for environment variables and constants
   - Add comments for complex logic
   - Use functions for reusable code

3. **Error Handling**:
   - Always check command exit codes
   - Provide clear error messages
   - Use the `log()` function from `common/utils.sh`
   - Implement cleanup on failure

4. **Example**:
   ```bash
   #!/bin/bash
   set -euo pipefail
   
   # Source common utilities
   source "$(dirname "$0")/common/utils.sh"
   
   # Function to do something
   do_something() {
       local input="$1"
       
       if ! validate_input "$input"; then
           log "ERROR" "Invalid input: $input"
           return 1
       fi
       
       log "INFO" "Processing: $input"
       # ... implementation
   }
   ```

### Docker Configuration

- Use official images when possible
- Pin specific versions (avoid `latest` in production)
- Document all environment variables
- Use multi-stage builds if creating custom images
- Follow Docker best practices for security

### Documentation

- Update README.md for user-facing changes
- Add inline comments for complex logic
- Update templates if configuration changes
- Include examples for new features

## Submitting Changes

### Pull Request Process

1. **Update your branch** with the latest main:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Commit your changes** with clear messages:
   ```bash
   git commit -m "Add feature: brief description
   
   - Detailed point 1
   - Detailed point 2
   
   Fixes #123"
   ```

3. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

4. **Create a Pull Request** on GitHub:
   - Use the PR template
   - Link related issues
   - Describe what changed and why
   - Include testing details

### Commit Message Guidelines

Follow the conventional commits format:

```
<type>: <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Example**:
```
feat: add support for DigitalOcean deployment

- Add install-digitalocean.sh script
- Update common module to support DO API
- Add DO-specific configuration templates

Closes #45
```

### Code Review Process

1. Maintainers will review your PR
2. Address any feedback or requested changes
3. Once approved, a maintainer will merge your PR
4. Your contribution will be included in the next release

## Testing Guidelines

### Manual Testing

Before submitting a PR, test your changes on at least one platform:

- **For installation scripts**: Test full installation on a fresh instance
- **For common modules**: Test with multiple platforms
- **For Docker configs**: Test container startup and connectivity
- **For documentation**: Verify formatting and accuracy

### Test Checklist

- [ ] Script runs without errors
- [ ] All services start correctly
- [ ] MCP endpoint is accessible
- [ ] Error handling works as expected
- [ ] Idempotent (can run multiple times safely)
- [ ] Documentation is updated
- [ ] No sensitive data in commits

### Platform-Specific Testing

If your changes affect a specific platform:

- **GCP**: Test with `gcloud` CLI
- **AWS**: Test with `aws` CLI
- **Azure**: Test with `az` CLI
- **SSH**: Test with both password and key authentication

## Project Structure

```
graphiti-cloud-installer/
├── common/                 # Shared utilities and installation logic
│   ├── install-graphiti.sh # Core installation module
│   ├── utils.sh           # Utility functions
│   ├── validate.sh        # Validation scripts
│   └── uninstall.sh       # Cleanup scripts
├── docker/                # Docker configurations
│   ├── docker-compose-falkordb.yml
│   ├── docker-compose-neo4j.yml
│   └── nginx/             # NGINX configuration
├── templates/             # Configuration templates
├── examples/              # Example configurations and test scripts
├── test/                  # Test scripts
├── install-*.sh           # Platform-specific installation scripts
└── README.md              # Main documentation
```

## Getting Help

- **Questions**: Open a discussion on GitHub
- **Bugs**: Create an issue with the bug report template
- **Features**: Create an issue with the feature request template
- **Chat**: Join our community discussions

## Recognition

Contributors will be recognized in:
- The project README
- Release notes
- GitHub contributors page

Thank you for contributing to Graphiti Cloud Installer! 🎉
