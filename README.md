# Mount Management Script

## Description

This Bash script provides a user-friendly interface for managing systemd mount units. It allows for easy activation, deactivation, and management of both standard and custom mounts with enhanced error handling and user interaction.

## Key Features

- List all available mounts (including custom mounts)
- Activate and deactivate mounts
- Display mount file contents
- Handle errors (missing target directories, invalid mount files)
- Manage custom mounts in the systemd directory

## Prerequisites

- Bash shell
- sudo privileges
- systemd

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/mount-management-script.git
   ```
2. Change to the directory:
   ```
   cd mount-management-script
   ```
3. Make the script executable:
   ```
   chmod +x mount_management_script.sh
   ```

## Usage

Run the script with sudo privileges:

```
sudo ./mount_management_script.sh
```

Follow the prompts in the interactive menu to manage mounts.

## Features

- **Color-coded Menu**: Green for active, Red for inactive, and Yellow for mounts with errors.
- **Error Handling**: Automatic detection and resolution options for common issues.
- **Custom Mounts**: Support for mounts that only exist in the systemd directory.
- **Logging**: All actions are logged to a file for traceability.

## Security

- Checks for sudo privileges at startup
- Secure handling of filesystem operations
- Logging of all actions for traceability

## Contributing

Contributions are welcome! Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.

## Version History

- **v3.2** (2023-07-16): Improved handling of custom mounts, bug fixes
- **v3.1** (2023-07-15): Added support for custom mounts
- **v3.0** (2023-07-14): Initial release of the revamped script

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## Contact

Your Name - [@YourTwitter](https://twitter.com/YourTwitter) - email@example.com

Project Link: [https://github.com/yourusername/mount-management-script](https://github.com/yourusername/mount-management-script)