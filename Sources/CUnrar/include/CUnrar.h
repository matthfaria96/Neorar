// Thin C facade over RARLAB's UnRAR library, shaped for Swift.
//
// UnRAR source code may be used in any software to handle RAR archives without
// limitations free of charge, but cannot be used to develop RAR (WinRAR) compatible
// archiver and to re-create RAR compression algorithm, which is proprietary.
// Distribution of modified UnRAR source code in separate form or as a part of other
// software is permitted, provided that full text of this paragraph, starting from
// "UnRAR source code" words, is included in license, or in documentation if license
// is not available, and in source code comments of resulting package.

#ifndef CUNRAR_H
#define CUNRAR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Result codes (same values as ERAR_* in dll.hpp).
enum {
    NR_OK = 0,
    NR_END_ARCHIVE = 10,
    NR_NO_MEMORY = 11,
    NR_BAD_DATA = 12,
    NR_BAD_ARCHIVE = 13,
    NR_UNKNOWN_FORMAT = 14,
    NR_EOPEN = 15,
    NR_ECREATE = 16,
    NR_ECLOSE = 17,
    NR_EREAD = 18,
    NR_EWRITE = 19,
    NR_SMALL_BUF = 20,
    NR_UNKNOWN = 21,
    NR_MISSING_PASSWORD = 22,
    NR_EREFERENCE = 23,
    NR_BAD_PASSWORD = 24,
    NR_LARGE_DICT = 25,
};

enum { NR_OP_SKIP = 0, NR_OP_TEST = 1, NR_OP_EXTRACT = 2 };

// Archive flags (ROADF_*).
enum {
    NR_ARC_VOLUME = 0x0001,
    NR_ARC_COMMENT = 0x0002,
    NR_ARC_LOCK = 0x0004,
    NR_ARC_SOLID = 0x0008,
    NR_ARC_NEWNUMBERING = 0x0010,
    NR_ARC_SIGNED = 0x0020,
    NR_ARC_RECOVERY = 0x0040,
    NR_ARC_ENCHEADERS = 0x0080,
    NR_ARC_FIRSTVOLUME = 0x0100,
};

// Entry flags (RHDF_*).
enum {
    NR_ENTRY_SPLIT_BEFORE = 0x01,
    NR_ENTRY_SPLIT_AFTER = 0x02,
    NR_ENTRY_ENCRYPTED = 0x04,
    NR_ENTRY_SOLID = 0x10,
    NR_ENTRY_DIRECTORY = 0x20,
};

typedef struct nr_entry {
    const char *name;         // UTF-8 path inside the archive; valid until the next read
    uint64_t packed_size;
    uint64_t unpacked_size;
    double mtime;             // Unix seconds, 0 when absent
    uint32_t flags;           // NR_ENTRY_*
    uint32_t attributes;
    uint32_t crc;
    uint32_t host_os;
    uint32_t redir_type;      // non-zero for links
} nr_entry;

// Called for every decompressed block. Return non-zero to cancel.
typedef int (*nr_progress_fn)(void *context, int64_t bytes);

typedef struct nr_archive nr_archive;

// Opens an archive. `password` may be NULL. `result` receives an NR_* code.
nr_archive *nr_open(const char *path, int for_extraction, const char *password,
                    nr_progress_fn progress, void *context,
                    int *result, uint32_t *archive_flags);

// Reads the next header. Returns NR_OK, NR_END_ARCHIVE or an error.
int nr_read_header(nr_archive *archive, nr_entry *entry);

// Processes the current entry. `destination` is the directory the entry path is extracted under.
int nr_process(nr_archive *archive, int operation, const char *destination);

// True when UnRAR asked for a password that was not supplied.
int nr_password_was_requested(const nr_archive *archive);

// Archive comment (UTF-8), or empty.
const char *nr_comment(const nr_archive *archive);

// Name of the volume UnRAR could not find (UTF-8), or empty.
const char *nr_missing_volume(const nr_archive *archive);

void nr_close(nr_archive *archive);

#ifdef __cplusplus
}
#endif

#endif
