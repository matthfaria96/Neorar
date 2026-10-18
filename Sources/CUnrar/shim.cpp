// See CUnrar.h for the UnRAR license paragraph.

#include "rar.hpp"
#include "CUnrar.h"

#include <string>
#include <vector>

struct nr_archive {
    HANDLE handle = nullptr;
    nr_progress_fn progress = nullptr;
    void *context = nullptr;
    std::wstring password;
    bool has_password = false;
    bool password_requested = false;
    std::string missing_volume;
    std::string current_name;
    std::string comment;
};

static int CALLBACK nr_callback(UINT msg, LPARAM user_data, LPARAM p1, LPARAM p2) {
    auto *archive = reinterpret_cast<nr_archive *>(user_data);
    switch (msg) {
    case UCM_PROCESSDATA:
        if (archive->progress && archive->progress(archive->context, (int64_t)p2) != 0)
            return -1;
        return 1;
    case UCM_NEEDPASSWORDW: {
        if (!archive->has_password) {
            archive->password_requested = true;
            return -1;
        }
        auto *buffer = reinterpret_cast<wchar_t *>(p1);
        size_t size = (size_t)p2;
        if (size == 0) return -1;
        wcsncpy(buffer, archive->password.c_str(), size - 1);
        buffer[size - 1] = 0;
        return 1;
    }
    case UCM_NEEDPASSWORD:
        // Only reached when the wide request produced nothing.
        return -1;
    case UCM_CHANGEVOLUMEW:
        if (p2 == RAR_VOL_ASK) {
            std::string name;
            WideToUtf(std::wstring(reinterpret_cast<wchar_t *>(p1)), name);
            archive->missing_volume = name;
            return -1;
        }
        return 1;
    case UCM_CHANGEVOLUME:
        return p2 == RAR_VOL_ASK ? -1 : 1;
    case UCM_LARGEDICT:
        return 1; // Allow large dictionaries; memory is not scarce on a Mac.
    }
    return 0;
}

extern "C" nr_archive *nr_open(const char *path, int for_extraction, const char *password,
                                nr_progress_fn progress, void *context,
                                int *result, uint32_t *archive_flags) {
    auto *archive = new nr_archive();
    archive->progress = progress;
    archive->context = context;
    if (password && *password) {
        archive->has_password = UtfToWide(password, archive->password);
    }

    std::wstring wide_path;
    UtfToWide(path, wide_path);

    RAROpenArchiveDataEx data;
    memset(&data, 0, sizeof(data));
    data.ArcNameW = const_cast<wchar_t *>(wide_path.c_str());
    data.OpenMode = for_extraction ? RAR_OM_EXTRACT : RAR_OM_LIST;
    data.Callback = nr_callback;
    data.UserData = reinterpret_cast<LPARAM>(archive);
    std::vector<wchar_t> comment_buffer(65536, 0);
    data.CmtBufW = comment_buffer.data();
    data.CmtBufSize = (unsigned int)comment_buffer.size();

    archive->handle = RAROpenArchiveEx(&data);
    // CmtState: 1 = read, ERAR_SMALL_BUF = read but truncated.
    if ((data.CmtState == 1 || data.CmtState == ERAR_SMALL_BUF) && comment_buffer[0] != 0) {
        comment_buffer.back() = 0;
        WideToUtf(std::wstring(comment_buffer.data()), archive->comment);
    }
    if (result) *result = (int)data.OpenResult;
    if (archive_flags) *archive_flags = data.Flags;
    if (archive->handle == nullptr || data.OpenResult != ERAR_SUCCESS) {
        if (result && data.OpenResult == ERAR_SUCCESS) *result = NR_UNKNOWN;
        if (archive->handle) RARCloseArchive(archive->handle);
        archive->handle = nullptr;
        // Keep the struct alive so the caller can read password/volume diagnostics.
    }
    return archive;
}

static double filetime_to_unix(uint32_t low, uint32_t high) {
    uint64_t ft = ((uint64_t)high << 32) | low;
    if (ft == 0) return 0;
    // FILETIME counts 100 ns intervals since 1601-01-01.
    return (double)((int64_t)ft - 116444736000000000LL) / 10000000.0;
}

extern "C" int nr_read_header(nr_archive *archive, nr_entry *entry) {
    if (!archive || !archive->handle) return NR_EOPEN;
    // RARHeaderDataEx is ~10 KB; keep it off small thread stacks.
    static thread_local RARHeaderDataEx header;
    memset(&header, 0, sizeof(header));
    int code = RARReadHeaderEx(archive->handle, &header);
    if (code != ERAR_SUCCESS) return code;

    // WideToUtf appends to its destination.
    archive->current_name.clear();
    WideToUtf(std::wstring(header.FileNameW), archive->current_name);
    entry->name = archive->current_name.c_str();

    entry->packed_size = ((uint64_t)header.PackSizeHigh << 32) | header.PackSize;
    entry->unpacked_size = ((uint64_t)header.UnpSizeHigh << 32) | header.UnpSize;
    entry->mtime = filetime_to_unix(header.MtimeLow, header.MtimeHigh);
    entry->flags = header.Flags;
    entry->attributes = header.FileAttr;
    entry->crc = header.FileCRC;
    entry->host_os = header.HostOS;
    entry->redir_type = header.RedirType;
    return NR_OK;
}

extern "C" int nr_process(nr_archive *archive, int operation, const char *destination) {
    if (!archive || !archive->handle) return NR_EOPEN;
    if (destination && *destination) {
        std::wstring wide_destination;
        UtfToWide(destination, wide_destination);
        return RARProcessFileW(archive->handle, operation,
                               const_cast<wchar_t *>(wide_destination.c_str()), nullptr);
    }
    return RARProcessFileW(archive->handle, operation, nullptr, nullptr);
}

extern "C" int nr_password_was_requested(const nr_archive *archive) {
    return archive && archive->password_requested ? 1 : 0;
}

extern "C" const char *nr_comment(const nr_archive *archive) {
    return archive ? archive->comment.c_str() : "";
}

extern "C" const char *nr_missing_volume(const nr_archive *archive) {
    return archive ? archive->missing_volume.c_str() : "";
}

extern "C" void nr_close(nr_archive *archive) {
    if (!archive) return;
    if (archive->handle) RARCloseArchive(archive->handle);
    delete archive;
}
