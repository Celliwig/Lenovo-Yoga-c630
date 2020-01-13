#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <string.h>
#include <libaudit.h>
#include <unistd.h>
#include <ev.h>
#include <errno.h>
#include <sys/mount.h>
#include "auditctl-llist.h"

int fd_audit, fd_kmsg;

void write_log(const char* log_msg) {
	if (fd_kmsg >= 0) {
		write(fd_kmsg, log_msg, strlen(log_msg));
	}
}

void monitoring(struct ev_loop *loop, struct ev_io *io, int revents) {
	const char prockey[] = "key=\"mount_proc\"";
	struct audit_reply reply;

	int rc = audit_get_reply(fd_audit, &reply, GET_REPLY_NONBLOCKING, 0);
	if (rc > 0) {
		/* If we get done or error, break out */
		if (reply.type == NLMSG_DONE)
			return;

		if (reply.type == NLMSG_ERROR && reply.error->error)
			return;

		if (reply.type == AUDIT_SYSCALL && (strstr(reply.message, prockey) != NULL)) {
			//printf("Event: Type=%s Message=%.*s\n",
			//	audit_msg_type_to_name(reply.type),
			//	reply.len,
			//	reply.message);

			rc = mount("/.cmdline-alt", "/proc/cmdline", "none", MS_BIND, NULL);
			if (rc == 0) {
				write_log("cmdline-patch: Patched cmdline.");
			} else {
				write_log("cmdline-patch: Failed to patched cmdline.");
			}

			ev_break(EV_A_ EVBREAK_ALL);
		}
	}
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
	if (fd_kmsg >= 0)
		close(fd_kmsg);
}

int main(int argc, char** argv) {
	int rc, fd_cmdline;
	struct audit_rule_data* rule_new;

	if (argc != 2) {
		printf("Usage: %s <kernel args>\n", argv[0]);
		return -1;
	}

	// Write replacement cmdline file
	fd_cmdline = open("/.cmdline-alt", O_CREAT | O_WRONLY);
	if (fd_cmdline < 0) {
		printf("Error: Could not write replacement cmdline file.\n");
		return -1;
	} else {
		write(fd_cmdline, argv[1], strlen(argv[1]));
		close(fd_cmdline);
	}

	// Log to dmesg if possible
	fd_kmsg = open("/dev/kmsg", O_WRONLY);

	// Renice to higher priority level
	rc = nice(-4);
	if (rc == -1 && errno)
		write_log("cmdline-patch: Could not change nice level.");

	// Open handle to audit subsystem
	fd_audit = audit_open();
	if (fd_audit >= 0) {
		// Delete any existing rules
		rc = delete_all_rules(fd_audit);
		if (rc != 0) {
			printf("Error: Could not delete existing rules.\n");
			clean_up();
			return -1;
		}

		// Generate new rule to monitor mounting of '/proc'
		rule_new = new audit_rule_data();
		audit_rule_syscallbyname_data(rule_new, "mount");
		// Set extra filters
		char arch[] = "arch=b64";
		audit_rule_fieldpair_data(&rule_new, arch, AUDIT_FILTER_EXIT);
		char path[] = "path=/proc";
		audit_rule_fieldpair_data(&rule_new, path, AUDIT_FILTER_EXIT);
		char key[] = "key=mount_proc";
		audit_rule_fieldpair_data(&rule_new, key, AUDIT_FILTER_EXIT);
		rc = audit_add_rule_data(fd_audit, rule_new, AUDIT_FILTER_EXIT, AUDIT_ALWAYS);
		if (rc <= 0) {
			printf("Error: Could not add new rule.\n");
			clean_up();
			return -1;
		}

		if ((audit_is_enabled(fd_audit) < 2) && (audit_set_enabled(fd_audit, 1) < 0)) {
			printf("Error: Failed to enable audit.\n");
			clean_up();
			return -1;
		}
		if (audit_set_pid(fd_audit, getpid(), WAIT_YES) < 0) {
			printf("Error: Failed to set pid.\n");
			clean_up();
			return -1;
		}

		struct ev_io monitor;
		struct ev_loop *loop = ev_default_loop(EVFLAG_NOENV);

		ev_io_init(&monitor, monitoring, fd_audit, EV_READ);
		ev_io_start(loop, &monitor);

		ev_run(loop, 0);

		ev_io_stop (loop, &monitor);
		ev_default_destroy();
	} else {
		printf("Error: Failed to open audit subsystem.\n");
		clean_up();
		return -1;
	}

	write_log("cmdline-patch: Finished.");
	clean_up();
	return 0;
}
