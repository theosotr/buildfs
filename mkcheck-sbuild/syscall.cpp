// This file is part of the mkcheck project.
// Licensing information can be found in the LICENSE file.
// (C) 2017 Nandor Licker. All rights reserved.

#include "syscall.h"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

#include <fcntl.h>
#include <sys/eventfd.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>

#include "proc.h"
#include "trace.h"
#include "util.h"



// -----------------------------------------------------------------------------
static void sys_read(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddInput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_write(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddOutput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_open(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));
  const uint64_t flags = args[1];
  const int fd = args.Return;

  if (args.Return >= 0) {
    proc->MapFd(fd, path);
    proc->SetCloseExec(fd, flags & O_CLOEXEC);
  }
}

// -----------------------------------------------------------------------------
static void sys_close(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->CloseFd(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_stat(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));
  if (args.Return >= 0) {
    proc->AddTouched(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_fstat(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddTouched(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_lstat(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));

  if (args.Return >= 0) {
    proc->AddTouched(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_mmap(Process *proc, const Args &args)
{
  const int prot = args[2];
  const int flags = args[3];
  const int fd = args[4];

  if (args.Return != MAP_ANON && fd != -1) {
    // Writes are only carried out to the file in shared, writable mappings.
    if ((flags & MAP_SHARED) && (prot & PROT_WRITE)) {
      proc->AddOutput(fd);
    } else {
      proc->AddInput(fd);
    }
  }
}

// -----------------------------------------------------------------------------
static void sys_pread64(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddInput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_readv(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddInput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_writev(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddInput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_access(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));

  if (args.Return >= 0) {
    proc->AddTouched(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_pipe(Process *proc, const Args &args)
{
  int fds[2];
  ReadBuffer(args.PID, fds, args[0], 2 * sizeof(int));
  if (args.Return >= 0) {
    proc->Pipe(fds[0], fds[1]);
  }
}

// -----------------------------------------------------------------------------
static void sys_dup(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->DupFd(args[0], args.Return);
  }
}

// -----------------------------------------------------------------------------
static void sys_dup2(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->DupFd(args[0], args.Return);
  }
}

// -----------------------------------------------------------------------------
static void sys_socket(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->MapFd(args.Return, "/proc/network");
  }
}

// -----------------------------------------------------------------------------
static void sys_fcntl(Process *proc, const Args &args)
{
  const int fd = args[0];
  const int cmd = args[1];

  if (args.Return >= 0) {
    switch (cmd) {
      case F_DUPFD: {
        proc->DupFd(args[0], args.Return);
        break;
      }
      case F_DUPFD_CLOEXEC: {
        proc->DupFd(args[0], args.Return);
        proc->SetCloseExec(args.Return, false);
        break;
      }
      case F_SETFD: {
        const int arg = args[2];
        proc->SetCloseExec(fd, arg & FD_CLOEXEC);
        break;
      }
      case F_GETFD:
      case F_GETFL:
      case F_SETFL: {
        break;
      }
      case F_GETLK:
      case F_SETLK:
      case F_SETLKW: {
        break;
      }
      case F_OFD_GETLK:
      case F_OFD_SETLK:
      case F_OFD_SETLKW: {
        break;
      }
      default: {
        throw std::runtime_error(
            "Unknown fnctl (cmd = " + std::to_string(cmd) + ")"
        );
      }
    }
  }
}

// -----------------------------------------------------------------------------
static void sys_ftruncate(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddOutput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_getdents(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddInput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_chdir(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));

  if (args.Return >= 0) {
    proc->SetCwd(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_fchdir(Process *proc, const Args &args)
{
  const int fd = args[0];
  if (args.Return >= 0) {
    proc->SetCwd(proc->GetFd(fd));
  }
}

// -----------------------------------------------------------------------------
static void sys_rename(Process *proc, const Args &args)
{
  const fs::path src = proc->Normalise(ReadString(args.PID, args[0]));
  const fs::path dst = proc->Normalise(ReadString(args.PID, args[1]));

  if (args.Return >= 0) {
    proc->Rename(src, dst);
  }
}

// -----------------------------------------------------------------------------
static void sys_mkdir(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));

  if (args.Return >= 0) {
    proc->AddOutput(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_rmdir(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));

  if (args.Return >= 0) {
    proc->Remove(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_link(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    const fs::path srcRel = ReadString(args.PID, args[0]);
    const fs::path dstRel = ReadString(args.PID, args[1]);

    const fs::path src = proc->Normalise(srcRel);
    const fs::path dstParent = proc->Normalise(dstRel.parent_path());

    proc->Link(src, dstParent / dstRel.filename());
  }
}

// -----------------------------------------------------------------------------
static void sys_creat(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));
  const uint64_t flags = args[1];

  if (args.Return >= 0) {
    const int fd = args.Return;
    proc->MapFd(fd, path);
    proc->SetCloseExec(fd, flags & O_CLOEXEC);
  }
}

// -----------------------------------------------------------------------------
static void sys_unlink(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));

  if (args.Return >= 0) {
    proc->Remove(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_symlink(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    const fs::path src = ReadString(args.PID, args[0]);
    const fs::path dst = ReadString(args.PID, args[1]);

    const fs::path parent = proc->Normalise(dst.parent_path());
    const fs::path srcPath = proc->Normalise(src, parent);
    const fs::path dstPath = parent / dst.filename();

    // configure seems to create links pointing to themselves, which we ignore.
    if (srcPath != dstPath) {
      proc->Link(srcPath, dstPath);
    }
  }
}

// -----------------------------------------------------------------------------
static void sys_readlink(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));
  if (args.Return >= 0) {
    proc->AddInput(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_utime(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddOutput(proc->Normalise(ReadString(args.PID, args[0])));
  }
}

// -----------------------------------------------------------------------------
static void sys_linkat(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    const fs::path srcRel = ReadString(args.PID, args[1]);
    const fs::path dstRel = ReadString(args.PID, args[3]);

    const fs::path src = proc->Normalise(args[0], srcRel);
    const fs::path dstParent = proc->Normalise(args[2], dstRel.parent_path());

    proc->Link(src, dstParent / dstRel.filename());
  }
}

// -----------------------------------------------------------------------------
static void sys_fsetxattr(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddOutput(proc->GetFd(args[0]));
  }
}

// -----------------------------------------------------------------------------
static void sys_getxattr(Process *proc, const Args &args)
{
  const fs::path path = ReadString(args.PID, args[0]);
  const fs::path parent = proc->Normalise(path.parent_path());
  if (args.Return >= 0) {
      proc->AddInput(parent / path.filename());
  }
}

// -----------------------------------------------------------------------------
static void sys_lgetxattr(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));
  if (args.Return >= 0) {
      proc->AddInput(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_llistxattr(Process *proc, const Args &args)
{
  const fs::path path = proc->Normalise(ReadString(args.PID, args[0]));
  if (args.Return >= 0) {
      proc->AddInput(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_flistxattr(Process *proc, const Args &args)
{
  throw std::runtime_error("not implemented");
}


// -----------------------------------------------------------------------------
static void sys_epoll_create(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->MapFd(args.Return, "/proc/" + std::to_string(args.PID) + "/epoll");
  }
}

// -----------------------------------------------------------------------------
static void sys_getdents64(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddInput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_openat(Process *proc, const Args &args)
{
  const int dirfd = args[0];
  const fs::path path = proc->Normalise(dirfd, ReadString(args.PID, args[1]));
  const uint64_t flags = args[2];
  if (args.Return >= 0) {
    const int fd = args.Return;
    proc->MapFd(fd, path);
    proc->SetCloseExec(fd, flags & O_CLOEXEC);
  }
}

// -----------------------------------------------------------------------------
static void sys_mkdirat(Process *proc, const Args &args)
{
  const int dirfd = args[0];
  const fs::path path = proc->Normalise(dirfd, ReadString(args.PID, args[1]));

  if (args.Return >= 0) {
    proc->AddOutput(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_newfstatat(Process *proc, const Args &args)
{
  const int dirfd = args[0];
  const fs::path path = proc->Normalise(dirfd, ReadString(args.PID, args[1]));

  if (args.Return >= 0) {
    proc->AddTouched(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_renameat(Process *proc, const Args &args)
{
  const int odirfd = args[0];
  const fs::path opath = proc->Normalise(odirfd, ReadString(args.PID, args[1]));
  const int ndirfd = args[2];
  const fs::path npath = proc->Normalise(ndirfd, ReadString(args.PID, args[3]));

  if (args.Return >= 0) {
    proc->Rename(opath, npath);
  }
}

// -----------------------------------------------------------------------------
static void sys_unlinkat(Process *proc, const Args &args)
{
  const int fd = args[0];
  const fs::path path = proc->Normalise(fd, ReadString(args.PID, args[1]));

  if (args.Return >= 0) {
    proc->Remove(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_readlinkat(Process *proc, const Args &args)
{
  const int fd = args[0];
  const fs::path path = proc->Normalise(fd, ReadString(args.PID, args[1]));
  if (args.Return >= 0) {
    proc->AddInput(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_faccessat(Process *proc, const Args &args)
{
  const int fd = args[0];
  const fs::path path = proc->Normalise(fd, ReadString(args.PID, args[1]));

  if (args.Return >= 0) {
    proc->AddInput(path);
  }
}

// -----------------------------------------------------------------------------
static void sys_splice(Process *proc, const Args &args)
{
  throw std::runtime_error("not implemented");
}

// -----------------------------------------------------------------------------
static void sys_fallocate(Process *proc, const Args &args)
{
  if (args.Return >= 0) {
    proc->AddOutput(args[0]);
  }
}

// -----------------------------------------------------------------------------
static void sys_eventfd2(Process *proc, const Args &args)
{
  const int flags = args[1];
  const int fd = args.Return;

  if (args.Return >= 0) {
    proc->MapFd(fd, "/proc/" + std::to_string(args.PID) + "/event");
    proc->SetCloseExec(fd, flags & EFD_CLOEXEC);
  }
}

// -----------------------------------------------------------------------------
static void sys_dup3(Process *proc, const Args &args)
{
  const int oldfd = args[0];
  const int newfd = args[1];
  const int flags = args[2];

  if (args.Return >= 0) {
    proc->DupFd(oldfd, newfd);
  }

  proc->SetCloseExec(newfd, flags & O_CLOEXEC);
}

// -----------------------------------------------------------------------------
static void sys_pipe2(Process *proc, const Args &args)
{
  int fds[2];
  ReadBuffer(args.PID, fds, args[0], 2 * sizeof(int));
  const int flags = args[1];

  if (args.Return >= 0) {
    proc->Pipe(fds[0], fds[1]);

    const bool closeExec = flags & O_CLOEXEC;
    proc->SetCloseExec(fds[0], closeExec);
    proc->SetCloseExec(fds[1], closeExec);
  }
}

// -----------------------------------------------------------------------------
static void sys_ignore(Process *proc, const Args &args)
{
}

typedef void (*HandlerFn) (Process *proc, const Args &args);

static const HandlerFn kHandlers[] =
{
  /* 0x000 */ [SYS_read              ] = sys_read,
  /* 0x001 */ [SYS_write             ] = sys_write,
  /* 0x002 */ [SYS_open              ] = sys_open,
  /* 0x003 */ [SYS_close             ] = sys_close,
  /* 0x004 */ [SYS_stat              ] = sys_stat,
  /* 0x005 */ [SYS_fstat             ] = sys_fstat,
  /* 0x006 */ [SYS_lstat             ] = sys_lstat,
  /* 0x007 */ [SYS_poll              ] = sys_ignore,
  /* 0x008 */ [SYS_lseek             ] = sys_ignore,
  /* 0x009 */ [SYS_mmap              ] = sys_mmap,
  /* 0x00A */ [SYS_mprotect          ] = sys_ignore,
  /* 0x00B */ [SYS_munmap            ] = sys_ignore,
  /* 0x00C */ [SYS_brk               ] = sys_ignore,
  /* 0x00D */ [SYS_rt_sigaction      ] = sys_ignore,
  /* 0x00E */ [SYS_rt_sigprocmask    ] = sys_ignore,
  /* 0x00F */ [SYS_rt_sigreturn      ] = sys_ignore,
  /* 0x010 */ [SYS_ioctl             ] = sys_ignore,
  /* 0x011 */ [SYS_pread64           ] = sys_pread64,
  /* 0x013 */ [SYS_readv             ] = sys_readv,
  /* 0x014 */ [SYS_writev            ] = sys_writev,
  /* 0x015 */ [SYS_access            ] = sys_access,
  /* 0x016 */ [SYS_pipe              ] = sys_pipe,
  /* 0x017 */ [SYS_select            ] = sys_ignore,
  /* 0x018 */ [SYS_sched_yield       ] = sys_ignore,
  /* 0x019 */ [SYS_mremap            ] = sys_ignore,
  /* 0x01a */ [SYS_msync             ] = sys_ignore,
  /* 0x01b */ [SYS_mincore           ] = sys_ignore,
  /* 0x01c */ [SYS_madvise           ] = sys_ignore,
  /* 0x020 */ [SYS_dup               ] = sys_dup,
  /* 0x021 */ [SYS_dup2              ] = sys_dup2,
  /* 0x023 */ [SYS_nanosleep         ] = sys_ignore,
  /* 0x025 */ [SYS_alarm             ] = sys_ignore,
  /* 0x026 */ [SYS_setitimer         ] = sys_ignore,
  /* 0x027 */ [SYS_getpid            ] = sys_ignore,
  /* 0x029 */ [SYS_socket            ] = sys_socket,
  /* 0x02A */ [SYS_connect           ] = sys_ignore,
  /* 0x02C */ [SYS_sendto            ] = sys_ignore,
  /* 0x02D */ [SYS_recvfrom          ] = sys_ignore,
  /* 0x02E */ [SYS_sendmsg           ] = sys_ignore,
  /* 0x02F */ [SYS_recvmsg           ] = sys_ignore,
  /* 0x031 */ [SYS_bind              ] = sys_ignore,
  /* 0x033 */ [SYS_getsockname       ] = sys_ignore,
  /* 0x034 */ [SYS_getpeername       ] = sys_ignore,
  /* 0x035 */ [SYS_socketpair        ] = sys_ignore,
  /* 0x036 */ [SYS_setsockopt        ] = sys_ignore,
  /* 0x037 */ [SYS_getsockopt        ] = sys_ignore,
  /* 0x038 */ [SYS_clone             ] = sys_ignore,
  /* 0x039 */ [SYS_fork              ] = sys_ignore,
  /* 0x03A */ [SYS_vfork             ] = sys_ignore,
  /* 0x03B */ [SYS_execve            ] = sys_ignore,
  /* 0x03D */ [SYS_wait4             ] = sys_ignore,
  /* 0x03F */ [SYS_uname             ] = sys_ignore,
  /* 0x048 */ [SYS_fcntl             ] = sys_fcntl,
  /* 0x049 */ [SYS_flock             ] = sys_ignore,
  /* 0x04A */ [SYS_fsync             ] = sys_ignore,
  /* 0x04D */ [SYS_ftruncate         ] = sys_ftruncate,
  /* 0x04E */ [SYS_getdents          ] = sys_getdents,
  /* 0x04F */ [SYS_getcwd            ] = sys_ignore,
  /* 0x050 */ [SYS_chdir             ] = sys_chdir,
  /* 0x051 */ [SYS_fchdir            ] = sys_fchdir,
  /* 0x052 */ [SYS_rename            ] = sys_rename,
  /* 0x053 */ [SYS_mkdir             ] = sys_mkdir,
  /* 0x054 */ [SYS_rmdir             ] = sys_rmdir,
  /* 0x055 */ [SYS_creat             ] = sys_creat,
  /* 0x056 */ [SYS_link              ] = sys_link,
  /* 0x057 */ [SYS_unlink            ] = sys_unlink,
  /* 0x058 */ [SYS_symlink           ] = sys_symlink,
  /* 0x059 */ [SYS_readlink          ] = sys_readlink,
  /* 0x05A */ [SYS_chmod             ] = sys_ignore,
  /* 0x05B */ [SYS_fchmod            ] = sys_ignore,
  /* 0x05C */ [SYS_chown             ] = sys_ignore,
  /* 0x05F */ [SYS_umask             ] = sys_ignore,
  /* 0x060 */ [SYS_gettimeofday      ] = sys_ignore,
  /* 0x061 */ [SYS_getrlimit         ] = sys_ignore,
  /* 0x062 */ [SYS_getrusage         ] = sys_ignore,
  /* 0x063 */ [SYS_sysinfo           ] = sys_ignore,
  /* 0x064 */ [SYS_times             ] = sys_ignore,
  /* 0x066 */ [SYS_getuid            ] = sys_ignore,
  /* 0x068 */ [SYS_getgid            ] = sys_ignore,
  /* 0x06B */ [SYS_geteuid           ] = sys_ignore,
  /* 0x06C */ [SYS_getegid           ] = sys_ignore,
  /* 0x06D */ [SYS_setpgid           ] = sys_ignore,
  /* 0x06E */ [SYS_getppid           ] = sys_ignore,
  /* 0x06F */ [SYS_getpgrp           ] = sys_ignore,
  /* 0x070 */ [SYS_setsid            ] = sys_ignore,
  /* 0x071 */ [SYS_setreuid          ] = sys_ignore,
  /* 0x073 */ [SYS_getgroups         ] = sys_ignore,
  /* 0x07F */ [SYS_rt_sigpending     ] = sys_ignore,
  /* 0x083 */ [SYS_sigaltstack       ] = sys_ignore,
  /* 0x084 */ [SYS_utime             ] = sys_utime,
  /* 0x087 */ [SYS_personality       ] = sys_ignore,
  /* 0x089 */ [SYS_statfs            ] = sys_ignore,
  /* 0x08A */ [SYS_fstatfs           ] = sys_ignore,
  /* 0x09D */ [SYS_prctl             ] = sys_ignore,
  /* 0x09E */ [SYS_arch_prctl        ] = sys_ignore,
  /* 0x0A0 */ [SYS_setrlimit         ] = sys_ignore,
  /* 0x0A5 */ [SYS_linkat            ] = sys_linkat,
  /* 0x0BA */ [SYS_gettid            ] = sys_ignore,
  /* 0x0BE */ [SYS_fsetxattr         ] = sys_fsetxattr,
  /* 0x0BF */ [SYS_getxattr          ] = sys_getxattr,
  /* 0x0C0 */ [SYS_lgetxattr         ] = sys_lgetxattr,
  /* 0x0C3 */ [SYS_llistxattr        ] = sys_llistxattr,
  /* 0x0C4 */ [SYS_flistxattr        ] = sys_flistxattr,
  /* 0x0C9 */ [SYS_time              ] = sys_ignore,
  /* 0x0CA */ [SYS_futex             ] = sys_ignore,
  /* 0x0CB */ [SYS_sched_setaffinity ] = sys_ignore,
  /* 0x0CC */ [SYS_sched_getaffinity ] = sys_ignore,
  /* 0x0D5 */ [SYS_epoll_create      ] = sys_epoll_create,
  /* 0x0D9 */ [SYS_getdents64        ] = sys_getdents64,
  /* 0x0DA */ [SYS_set_tid_address   ] = sys_ignore,
  /* 0x0DB */ [SYS_restart_syscall   ] = sys_ignore,
  /* 0x0DE */ [SYS_timer_create      ] = sys_ignore,
  /* 0x0DF */ [SYS_timer_settime     ] = sys_ignore,
  /* 0x0E0 */ [SYS_timer_gettime     ] = sys_ignore,
  /* 0x0E1 */ [SYS_timer_getoverrun  ] = sys_ignore,
  /* 0x0E2 */ [SYS_timer_delete      ] = sys_ignore,
  /* 0x0DD */ [SYS_fadvise64         ] = sys_ignore,
  /* 0x0E4 */ [SYS_clock_gettime     ] = sys_ignore,
  /* 0x0E5 */ [SYS_clock_getres      ] = sys_ignore,
  /* 0x0E7 */ [SYS_exit_group        ] = sys_ignore,
  /* 0x0E8 */ [SYS_epoll_wait        ] = sys_ignore,
  /* 0x0E9 */ [SYS_epoll_ctl         ] = sys_ignore,
  /* 0x0EA */ [SYS_tgkill            ] = sys_ignore,
  /* 0x0EB */ [SYS_utimes            ] = sys_ignore,
  /* 0x0F7 */ [SYS_waitid            ] = sys_ignore,
  /* 0x101 */ [SYS_openat            ] = sys_openat,
  /* 0x102 */ [SYS_mkdirat           ] = sys_mkdirat,
  /* 0x106 */ [SYS_newfstatat        ] = sys_newfstatat,
  /* 0x107 */ [SYS_unlinkat          ] = sys_unlinkat,
  /* 0x108 */ [SYS_renameat          ] = sys_renameat,
  /* 0x10B */ [SYS_readlinkat        ] = sys_readlinkat,
  /* 0x10C */ [SYS_fchmodat          ] = sys_ignore,
  /* 0x10D */ [SYS_faccessat         ] = sys_faccessat,
  /* 0x10E */ [SYS_pselect6          ] = sys_ignore,
  /* 0x10F */ [SYS_ppoll             ] = sys_ignore,
  /* 0x111 */ [SYS_set_robust_list   ] = sys_ignore,
  /* 0x113 */ [SYS_splice            ] = sys_splice,
  /* 0x118 */ [SYS_utimensat         ] = sys_ignore,
  /* 0x119 */ [SYS_epoll_pwait       ] = sys_ignore,
  /* 0x11D */ [SYS_fallocate         ] = sys_fallocate,
  /* 0x122 */ [SYS_eventfd2          ] = sys_eventfd2,
  /* 0x123 */ [SYS_epoll_create1     ] = sys_ignore,
  /* 0x124 */ [SYS_dup3              ] = sys_dup3,
  /* 0x125 */ [SYS_pipe2             ] = sys_pipe2,
  /* 0x12E */ [SYS_prlimit64         ] = sys_ignore,
  /* 0x133 */ [SYS_sendmmsg          ] = sys_ignore,
  /* 0x13E */ [SYS_getrandom         ] = sys_ignore,
};

// -----------------------------------------------------------------------------
void Handle(Trace *trace, int64_t sno, const Args &args)
{
  if (sno < 0) {
    return;
  }

  if (sno > sizeof(kHandlers) / sizeof(kHandlers[0]) || !kHandlers[sno]) {
    return;
  }

  auto *proc = trace->GetTrace(args.PID);

  try {
    kHandlers[sno](proc, args);
  } catch (std::exception &ex) {
    throw std::runtime_error(
        "Exception while handling syscall " + std::to_string(sno) +
        " in process " + std::to_string(proc->GetUID()) + " (" +
        trace->GetFileName(proc->GetImage()) +
        "): " +
        ex.what()
    );
  }
}
