(*
 * Copyright (c) 2018-2020 Thodoris Sotiropoulos
 *
 * This program is free software: you can redistribute it and/or modify  
 * it under the terms of the GNU General Public License as published by  
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but 
 * WITHOUT ANY WARRANTY; without even the implied warranty of 
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License 
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *)


exception DomainError of string
(** Exception that is raised when we perform invalid operations
  on the analysis state. *)


type syscall_effect =
  | Create of string
  | Read of string
  | Remove of string
  | Touch of string
  | Write of string
(** Type that holds the effect that a system call might have
  on the file system. *)


type abstraction_effect =
  | Consumed of string
  | Modified of string
  | Produced of string
  | Expunged of string
(** Type that holds the effects that higher-level constructs, such as
  build tasks, might have on the file system. *)


type effect = (syscall_effect * Syntax.syscall_desc)
(** A type that represents an effect of a system call.*)


type process = string
(** Type that represents a process. *)


type addr_t
(** Type representing the address used to store file descriptor table
    and working directory of a process. *)


type fd = string
(** Type that represents a file descriptor. *)


type filename = string
(** Type that represents a file name. *)


type effect_store
(** A list that contains  the effect of a system call on the file system. *)


type proc_store


type proc_fd_store
(** The type that represents the file descriptor table of a process. *)


type fd_store
(** The type for the file descriptor table. *)


type cwd_store
(** The type for the current working directory table. *)


type symlink_store
(** The type for the symbolic link table. *)


type task_block = string list
(** The type that represents the ID of the current execution block. *)


type parent_process = string option
(** The type that represents the process of the tool. *)


type state = 
  {k:  proc_store;
   r:  fd_store;
   c:  effect_store;
   d:  cwd_store;
   s:  symlink_store;
   g:  int Stream.t;
   b:  task_block;
   o:  task_block;
   z:  parent_process;
   f:  Graph.graph;
   q:  Util.StringSet.t;
   e:  string option;
  }
(** Abstract type that represents the state in BuildFS. *)


val gen_addr : state -> addr_t
(** Generates a fresh address. *)


val init_state : unit -> state
(** Initializes the state of the analysis. *)


val get_effects : state -> effect list
(** Retrieves the list of the effects of the current execution block. *)


val reset_effect_store : state -> state
(** Resets the effect store from the given state. *)


val find_from_cwdtable : process -> proc_store -> cwd_store -> filename option 
(** This function gets the filename of the working directory
  of the given process. *)


val find_proc_fdtable : process
  -> proc_store
  -> fd_store
  -> proc_fd_store option
(** This function gets the file descriptor table of a process. *)


val find_from_fdtable : process -> fd -> proc_store -> fd_store -> filename option
(** This function finds the filename that corresponds to an open
  file descriptor with regards to the table of the provided process. *)


val find_from_symtable : filename -> symlink_store -> filename option
(** Gets the path to which the given inode points. *)


val find_from_proctable : process -> proc_store -> (addr_t * addr_t) option
(** Finds the pair of addresses of a processes.
    
    These addresses are used to store the working directory and
    the file descriptor table of that process respectively. *)


val add_to_cwdtable : process -> filename -> proc_store -> cwd_store -> cwd_store
(** This functions add a new entry to the table of working directories.
  Specifically, it associates a process with its current working directory. *)


val add_to_fdtable : process
  -> fd
  -> filename option
  -> proc_store
  -> fd_store
  -> fd_store
(** This function adds a new entry to the file descriptor table.
  It creates an entry with the given file descriptor and filename to
  the file descriptor table of the current process. *)


val add_to_symtable : filename -> filename -> symlink_store -> symlink_store
(** This function adds a new entry to the symbolic link table. *)


val remove_from_fdtable : process -> fd -> proc_store -> fd_store -> fd_store
(** This function removes an entry (i.e., pid, fd) from the file
  file descriptor table. *)


val init_proc_cwdtable : addr_t -> cwd_store -> cwd_store
(** Initializes the working directory of a process
    stored in the given address. *)


val init_proc_fdtable : addr_t -> fd_store -> fd_store
(** Initializes the file descriptor table of a process
    stored in the given address. *)


val add_to_proctable : process
  -> addr_t
  -> addr_t
  -> proc_store
  -> proc_store
(** Adds the given addresses to the process table of the specified process. *)


val copy_cwdtable : process -> addr_t -> proc_store -> cwd_store -> cwd_store
(** It copies the working directory of the first process to the second one. *)


val copy_fdtable : process -> addr_t -> proc_store -> fd_store -> fd_store
(** It copies the file descriptor table of the first process to the
  second one. *)


val copy_fd : process -> fd -> fd -> proc_store -> fd_store -> fd_store
(** This function copies the file descriptor of a given process. *)


val add_effect : effect_store -> (syscall_effect * Syntax.syscall_desc) -> effect_store
(** This function adds the effect of a particular system call to the list of effects. *)


val unique_effects : effect list -> effect list
(** Gets the unique system calls effects from a given list. *)


val get_parent_dir : process -> state -> Syntax.fd_var -> string option
(** Gets the directory corresponding to the given file descriptor variable. *)


val get_pathname : process -> state -> Syntax.fd_var -> Syntax.path -> Syntax.path option
(** This function gets a path and a file descriptor and constructs
  an absolute path.
  
  If the given path is not absolute, this function interprets it as
  relative to the given file descriptor. *)


val extract_task : abstraction_effect * Syntax.syscall_desc -> string
(** Extracts the name of the task from the given effect. *)
