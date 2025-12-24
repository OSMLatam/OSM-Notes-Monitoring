# Contributing to OSM-Notes-Monitoring

Thank you for your interest in contributing to OSM-Notes-Monitoring! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

- Be respectful and considerate of others
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Follow the project's coding standards

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/OSM-Notes-Monitoring.git`
3. Create a branch for your changes: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes
6. Commit your changes with clear messages
7. Push to your fork: `git push origin feature/your-feature-name`
8. Create a Pull Request

## Development Guidelines

### Code Style

- **Shell Scripts**: Follow bash best practices, use `shellcheck` for linting
- **SQL**: Use consistent formatting, include comments for complex queries
- **Documentation**: Keep documentation up-to-date with code changes

### Commit Messages

Use clear, descriptive commit messages:

```
Short summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
Explain what and why, not how.
```

### Testing

- Write tests for new monitoring scripts
- Test configuration changes in a development environment
- Verify SQL queries work correctly before committing

### Documentation

- Update README.md if adding new features
- Add comments to complex code sections
- Update CHANGELOG.md for significant changes

## Project Structure

- `bin/` - Executable scripts (monitoring, security, alerts, dashboards)
- `sql/` - SQL queries organized by component
- `config/` - Configuration file templates
- `dashboards/` - Dashboard files (Grafana JSON, HTML)
- `docs/` - Documentation files
- `tests/` - Test suite

## Reporting Issues

When reporting issues, please include:

- Description of the problem
- Steps to reproduce
- Expected behavior
- Actual behavior
- Environment details (OS, PostgreSQL version, etc.)
- Relevant logs or error messages

## Feature Requests

For feature requests, please:

- Describe the feature clearly
- Explain the use case
- Discuss potential implementation approaches (if you have ideas)

## Pull Request Process

1. Ensure your code follows the project's style guidelines
2. Update documentation as needed
3. Add tests if applicable
4. Ensure all tests pass
5. Update CHANGELOG.md
6. Request review from maintainers

## Questions?

If you have questions, feel free to:

- Open an issue for discussion
- Contact the maintainers

Thank you for contributing to OSM-Notes-Monitoring!

