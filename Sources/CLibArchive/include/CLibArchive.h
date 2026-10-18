// Declarations for the subset of libarchive used by Neorar. macOS ships libarchive in
// /usr/lib but not its headers; these prototypes match libarchive 3.x's stable C ABI.
#ifndef CLIBARCHIVE_H
#define CLIBARCHIVE_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

#define ARCHIVE_EXTRACT_PERM 0x0002
#define ARCHIVE_EXTRACT_TIME 0x0004
#define ARCHIVE_EXTRACT_ACL 0x0020
#define ARCHIVE_EXTRACT_FFLAGS 0x0040
#define ARCHIVE_EXTRACT_XATTR 0x0080
#define ARCHIVE_EXTRACT_SECURE_SYMLINKS 0x0100
#define ARCHIVE_EXTRACT_SECURE_NODOTDOT 0x0200
#define ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS 0x10000

#define AE_IFMT 0170000
#define AE_IFREG 0100000
#define AE_IFLNK 0120000
#define AE_IFDIR 0040000

struct archive;
struct archive_entry;

const char *archive_version_string(void);

struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
int archive_read_data_skip(struct archive *);
int archive_read_extract2(struct archive *, struct archive_entry *, struct archive *dest);
int archive_read_free(struct archive *);

struct archive *archive_write_disk_new(void);
int archive_write_disk_set_options(struct archive *, int flags);
int archive_write_disk_set_standard_lookup(struct archive *);
int archive_write_free(struct archive *);

const char *archive_error_string(struct archive *);
int archive_errno(struct archive *);
int64_t archive_filter_bytes(struct archive *, int);
int archive_format(struct archive *);
const char *archive_format_name(struct archive *);

const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
void archive_entry_set_pathname_utf8(struct archive_entry *, const char *);
const char *archive_entry_hardlink(struct archive_entry *);
void archive_entry_set_hardlink(struct archive_entry *, const char *);
const char *archive_entry_symlink(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);

#endif
