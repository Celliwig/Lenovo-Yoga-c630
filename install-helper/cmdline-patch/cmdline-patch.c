#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <string.h>
#include <libaudit.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mount.h>
#include "auditctl-llist.h"

int fd_audit = -1, fd_log = -1;

void write_log(const char* log_msg, int cr) {
	char log_buffer[1024];

	if (fd_log >= 0) {
		if (cr) {
			snprintf(log_buffer, 1024, "cmdline-patch: %s\n", log_msg);
		} else {
			snprintf(log_buffer, 1024, "cmdline-patch: %s", log_msg);
		}

		write(fd_log, log_buffer, strlen(log_buffer));
		fsync(fd_log);
	}
}

void write_log_event(struct audit_reply reply, int cr) {
	char msg_buffer[1024];
	snprintf(msg_buffer, 1024, "Event: Type=%s Message=%s", audit_msg_type_to_name(reply.type), reply.message);
	write_log(msg_buffer, cr);
}

/* Returns 0 for success and -1 for failure */
int delete_all_rules(int fd_audit)
{
	int seq, i, rc, retval = 0;
	int timeout = 40; /* tenths of seconds */
	struct audit_reply rep;
	fd_set read_mask;
	llist l;
	lnode *n;

	/* list the rules */
	seq = audit_request_rules_list_data(fd_audit);
	if (seq <= 0)
		return -1;

	FD_ZERO(&read_mask);
	FD_SET(fd_audit, &read_mask);
	list_create(&l);

	for (i = 0; i < timeout; i++) {
		struct timeval t;

		t.tv_sec  = 0;
		t.tv_usec = 100000; /* .1 second */
		do {
			rc = select(fd_audit+1, &read_mask, NULL, NULL, &t);
		} while (rc < 0 && errno == EINTR);
		// We'll try to read just in case
		rc = audit_get_reply(fd_audit, &rep, GET_REPLY_NONBLOCKING, 0);
		if (rc > 0) {
			/* Reset timeout */
			i = 0;

			/* Don't make decisions based on wrong packet */
			if (rep.nlh->nlmsg_seq != seq)
				continue;

			/* If we get done or error, break out */
			if (rep.type == NLMSG_DONE)
				break;

			if (rep.type == NLMSG_ERROR && rep.error->error) {
				retval = -1;
				break;
			}

			/* If its not what we are expecting, keep looping */
			if (rep.type != AUDIT_LIST_RULES)
				continue;

			//if (key_match(rep.ruledata))
				list_append(&l, rep.ruledata,
					sizeof(struct audit_rule_data) +
					rep.ruledata->buflen);
		}
	}
	list_first(&l);
	n = l.cur;
	if (retval == 0) {
		while (n) {
			struct audit_rule_data *ruledata = n->r;
			rc = audit_delete_rule_data(fd_audit, ruledata, ruledata->flags, ruledata->action);
			if (rc < 0) {
				retval = -1;
				break;
			}
			n = list_next(&l);
		}
	}
	list_clear(&l);

	return retval;
}

void clean_up() {
	// Close audit subsystem handler
	if (fd_audit)
		audit_close(fd_audit);
	// Close log handler
	if (fd_log >= 0)
		close(fd_log);
}

void print_usage() {
	printf("Usage: cmdline-patch {options} <kernel args>\n");
	printf("	-d			- Log received events.\n");
	printf("	-k			- Log to /dev/kmsg.\n");
	printf("	-L <logfile path>	- Log to file.\n");
	printf("	-l			- Lock rules so they can't be altered.\n");
	printf("	-s			- Suppress rule insertion.\n");
}

int main(int argc, char** argv) {
	int add_rules = 1, fd_cmdline, i, lock_rules = 0, log_cr = 0, log_events = 0, loop = 1, opt, rc, retval = 0;
	int timeout = 40; /* tenths of seconds */
	struct audit_reply reply;
	struct audit_rule_data* rule_new;
	struct timeval t;
	fd_set master, read_fds;
	char *kernel_args, *log_path = NULL;
	const char prockey[] = "key=\"mount_proc\"";

	FD_ZERO(&master);
	FD_ZERO(&read_fds);
	FD_SET(fd_audit, &master);

	// Parse normal arguments
	while ((opt = getopt(argc, argv, "dkL:ls")) != -1) {
		switch (opt) {
			case 'd':
				log_events = 1;
				break;
			case 'k':
				log_cr = 0;
				log_path = (char*) "/dev/kmsg";
				break;
			case 'L':
				log_cr = 1;
				log_path = optarg;
				break;
			case 'l':
				lock_rules = 1;
				break;
			case 's':
				add_rules = 0;
				break;
			default:
				print_usage();
				return -1;
				break;
		}
	}
	if (optind == (argc - 1)) {
		kernel_args = argv[optind];
	} else {
		print_usage();
		return -1;
	}

	// Open log file
	if (log_path != NULL) {
		fd_log = open(log_path, O_CREAT | O_RDWR | O_APPEND);
	}

	// Write replacement cmdline file
	fd_cmdline = open("/.cmdline-alt", O_CREAT | O_WRONLY);
	if (fd_cmdline < 0) {
		write_log("Error: Could not write replacement cmdline file.", log_cr);
		return -1;
	} else {
		write(fd_cmdline, kernel_args, strlen(kernel_args));
		write(fd_cmdline, "\n", 1);
		close(fd_cmdline);
	}

	// Renice to higher priority level
	rc = nice(-4);
	if (rc == -1 && errno)
		write_log("Could not change nice level.", log_cr);

	// Open handle to audit subsystem
	fd_audit = audit_open();
	if (fd_audit >= 0) {
		if (add_rules) {
			// Delete any existing rules
			rc = delete_all_rules(fd_audit);
			if (rc != 0) {
				write_log("Error: Could not delete existing rules.", log_cr);
				clean_up();
				return -1;
			}
			write_log("Deleted existing rules.", log_cr);

			char rule_arch1[] = "arch=b32";
			char rule_arch2[] = "arch=b64";
			char rule_key1[] = "key=mount_proc";
			char rule_key2[] = "key=mount_proc";
			char rule_path1[] = "path=/proc";
			char rule_path2[] = "path=/proc";
			char rule_syscall1[] = "mount";
			char rule_syscall2[] = "mount";

			// Generate new rule to monitor mounting of '/proc'
			rule_new = (struct audit_rule_data *) malloc(sizeof(struct audit_rule_data));
			memset(rule_new, 0, sizeof(struct audit_rule_data));
			audit_rule_fieldpair_data(&rule_new, rule_arch1, AUDIT_FILTER_EXIT);
			audit_rule_syscallbyname_data(rule_new, rule_syscall1);
			audit_rule_fieldpair_data(&rule_new, rule_path1, AUDIT_FILTER_EXIT);
			audit_rule_fieldpair_data(&rule_new, rule_key1, AUDIT_FILTER_EXIT);
			rc = audit_add_rule_data(fd_audit, rule_new, AUDIT_FILTER_EXIT, AUDIT_ALWAYS);
			if (rc <= 0) {
				write_log("Error: Could not add new rule. [32]", log_cr);
				clean_up();
				return -1;
			}
			write_log("Added proc_mount rule. [32]", log_cr);

			// Generate new rule to monitor mounting of '/proc'
			rule_new = (struct audit_rule_data *) malloc(sizeof(struct audit_rule_data));
			memset(rule_new, 0, sizeof(struct audit_rule_data));
			audit_rule_fieldpair_data(&rule_new, rule_arch2, AUDIT_FILTER_EXIT);
			audit_rule_syscallbyname_data(rule_new, rule_syscall2);
			audit_rule_fieldpair_data(&rule_new, rule_path2, AUDIT_FILTER_EXIT);
			audit_rule_fieldpair_data(&rule_new, rule_key2, AUDIT_FILTER_EXIT);
			rc = audit_add_rule_data(fd_audit, rule_new, AUDIT_FILTER_EXIT, AUDIT_ALWAYS);
			if (rc <= 0) {
				write_log("Error: Could not add new rule. [64]", log_cr);
				clean_up();
				return -1;
			}
			write_log("Added proc_mount rule. [64]", log_cr);
		}

		if (lock_rules) {
			rc = audit_set_enabled(fd_audit, 2);
			if (rc == 0) {
				write_log("Locked rules.", log_cr);
			} else {
				write_log("Failed to lock rules.", log_cr);
			}
		}
		if ((audit_is_enabled(fd_audit) < 2) && (audit_set_enabled(fd_audit, 1) < 0)) {
			write_log("Error: Failed to enable audit.", log_cr);
			clean_up();
			return -1;
		}
		if (audit_set_pid(fd_audit, getpid(), WAIT_YES) < 0) {
			write_log("Error: Failed to set pid.", log_cr);
			clean_up();
			return -1;
		}

		write_log("Waiting.", log_cr);
		while (loop) {
			read_fds = master;

			for (i = 0; i < timeout; i++) {
				t.tv_sec  = 0;
				t.tv_usec = 100000; /* .1 second */
				do {
					rc = select(fd_audit+1, &read_fds, NULL, NULL, &t);
				} while (rc < 0 && errno == EINTR);
				// We'll try to read just in case
				rc = audit_get_reply(fd_audit, &reply, GET_REPLY_NONBLOCKING, 0);
				if (rc > 0) {
					/* Reset timeout */
					i = 0;

					///* Don't make decisions based on wrong packet */
					//if (reply.nlh->nlmsg_seq != seq)
					//	continue;

					/* If we get done or error, break out */
					if (reply.type == NLMSG_DONE)
						break;

					if (reply.type == NLMSG_ERROR && reply.error->error) {
						write_log("Failed - NLMSG_ERROR.", log_cr);
						clean_up();
						return -1;
					}

					if (log_events) {
						write_log_event(reply, log_cr);
					}

					if (reply.type == AUDIT_SYSCALL && (strstr(reply.message, prockey) != NULL)) {
						rc = mount("/.cmdline-alt", "/proc/cmdline", "none", MS_BIND, NULL);
						if (rc == 0) {
							write_log("Patched cmdline.", log_cr);
						} else {
							write_log("Failed to patched cmdline.", log_cr);
						}

						loop = 0;
					}
				}
			}
		}
	} else {
		write_log("Error: Failed to open audit subsystem.", log_cr);
		clean_up();
		return -1;
	}

	write_log("Finished.", log_cr);
	clean_up();
	return 0;
}
