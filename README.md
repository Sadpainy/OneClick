# ZeroClick Backdoor (Or OneClick) Post-Exploitation Trigger Framework

A research framework for studying zero-click post-exploitation trigger
mechanisms on Android devices. This project explores how a controlled
device can be triggered without any user interaction, using local
application databases as a dead drop channel.

This is a research and educational project. It contains no exploit
code, no shellcode, and no functional payloads. All modules are
skeletons that demonstrate architecture and logic only.

## Purpose

This framework demonstrates a post-exploitation technique that
achieves a zero-click experience for the victim. It does not rely on
a zero-day vulnerability. Instead, it relies on a device that is
already under control, combined with system-level persistence and
local database polling.

The goal is to document the design of such a trigger mechanism, to
support defensive research, detection engineering, and red team
training in controlled environments.

## Concept

A traditional zero-click exploit uses a vulnerability in message
parsing or media processing to execute code without user action. That
approach requires an unpatched vulnerability and a delivery vector
that the target automatically processes.

This framework takes a different path. It assumes the device is
already controlled. It then establishes persistence at the system
level and polls local application databases for a signed command.
When the command is found, the associated action is triggered.

From the victim's perspective, no interaction takes place. From a
technical perspective, no vulnerability is exploited. The trigger is
implemented through automation and persistence.

## Architecture

The framework is organized into modules, each with a single
responsibility. The modules are written as shell skeletons and PHP
skeletons. They contain logic and structure, but no weaponized
functionality.

Core modules:

- `ZCwizard.rc`
  Entry point for privilege escalation and self-start.

- `ZCV8XMP.dat.MDX`
  Polling library and trigger engine.

- `CZ3518.tmp`
  Rootkit skeleton for process, file, and port hiding.

- `directory.rc`
  Persistence directory management and partition mounting.

- `SHA256.sh1`
  Hash generation and command authentication.

- `Checksum.sh`
  Hash verification and integrity checking.

- `Decrypt.sh`
  Command decryption and payload decoding.

- `Messages.rc`
  System-level message dispatch and command delivery.

- `Printer.sh`
  Implant verification and environment probe.

- `Limux.sh`
  File sea camouflage and rootkit concealment.

- `Checker.sh`
  Connectivity test and network probe.

- `EXP.sh`
  Self-destruct and trace cleanup.

- `C2.php`
  Primary command and control server skeleton.

- `BackupC2.php`
  Backup command and control server skeleton.

- `DR000001.DBF`
  Zero-click log encrypted storage skeleton.

- `SX000002.INF`
  C2 communication log encrypted storage skeleton.

## Trigger Flow

The framework follows this sequence:

1. Persistence is established on a controlled device.
2. A polling script reads local application databases at a fixed
   interval.
3. The operator sends a message containing a signed hash.
4. The polling script reads the message from the local database.
5. The hash is extracted, verified, and decrypted.
6. The associated action is executed.
7. No user interaction occurs at any point.

The local databases used as dead drop channels are those maintained
by common messaging applications. Because these databases are stored
locally and updated automatically, they provide a reliable and
low-noise channel for command delivery.

## Design Principles

The framework follows several design principles:

- No reliance on zero-day vulnerabilities.
- No reliance on remote code execution.
- No reliance on user interaction.
- Modular structure with single-responsibility components.
- Encrypted command envelopes with replay protection.
- Redundant command and control channels.
- Trace cleanup and self-destruct support.

## Threat Model

This framework applies to a device that is already under control.
It does not cover initial access. It does not cover privilege
escalation from an unprivileged context. It assumes the operator
already has the required access and is looking for a low-noise
trigger mechanism.

The threat model is therefore:

- Target state: already controlled.
- Required access: root or equivalent.
- Required persistence: system partition or equivalent.
- Trigger channel: local application database.
- User interaction: none.

## Detection Considerations

Defenders can look for the following indicators:

- Unusual read access to messaging application databases.
- Persistent scripts in system or persist partitions.
- Unexpected entries in init configuration files.
- Periodic polling behavior with fixed intervals.
- Local databases containing hash-like strings in message bodies.
- Unexpected outbound connections to low-reputation domains.
- File system changes that create many decoy files.

Because the framework uses local databases and does not perform
aggressive network activity, network-based detection alone is
insufficient. Host-based monitoring and integrity checking are
required.

## Ethical and Legal Notice

This project is provided for lawful security research, red team
operations, and defensive evaluation only. You are solely
responsible for ensuring that your use complies with all applicable
laws, regulations, contracts, and authorizations.

You may not use this project to cause harm, to conduct unauthorized
access, or to violate the rights of any person. The original author
and contributors disclaim any responsibility for misuse.

## License

This project is licensed under the GNU Affero General Public
License, Version 3, with additional terms under Section 7.

See the License.OneClick file for the full text.

## Disclaimer

This project is a skeleton. It contains no functional payloads. It
is intended to document architecture, logic, and design decisions.
Any use of the concepts described here must be authorized and
lawful.

The authors provide no warranty of fitness for any particular
purpose. The authors provide no warranty of merchantability. The
authors provide no warranty of non-infringement.
