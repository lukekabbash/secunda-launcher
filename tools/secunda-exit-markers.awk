BEGIN {
    windows_access_violation_markers = 0
    host_crash_markers = 0
    fatal_runtime_markers = 0
}

{
    line = tolower($0)
    windows_access_violation = 0
    host_crash = 0
    fatal_runtime = 0

    if (line ~ /unhandled exception[^:]*:[[:space:]]*page fault/ ||
        line ~ /unhandled page fault/ ||
        line ~ /(^|[[:space:]{,])exception code[[:space:]:=]+(0x)?c0000005/ ||
        line ~ /(unhandled|fatal|crash|abnormal|terminated|process exited).*(0x)?c0000005/ ||
        line ~ /(0x)?c0000005.*(unhandled|fatal|crash|abnormal|terminated)/ ||
        line ~ /(unhandled|fatal|crash|abnormal|terminated|process exited).*3221225477/ ||
        line ~ /(unhandled|fatal|crash|abnormal|terminated|process exited).*-1073741819/) {
        windows_access_violation = 1
    }

    if (line ~ /exc_bad_access/ ||
        line ~ /segmentation fault/ ||
        line ~ /sigsegv/ ||
        line ~ /signal[[:space:]]+11([^0-9]|$)/ ||
        line ~ /bus error/ ||
        line ~ /sigbus/) {
        host_crash = 1
    }

    if (line ~ /assertion.*failed/ ||
        line ~ /fatal runtime error/ ||
        line ~ /stack overflow/ ||
        line ~ /out of memory/ ||
        line ~ /terminate called/ ||
        line ~ /abort trap/) {
        fatal_runtime = 1
    }

    windows_access_violation_markers += windows_access_violation
    host_crash_markers += host_crash
    fatal_runtime_markers += fatal_runtime
}

END {
    print "SECUNDA_EXIT_MARKERS_FORMAT=1"
    print "WINDOWS_ACCESS_VIOLATION_MARKERS=" windows_access_violation_markers
    print "HOST_CRASH_MARKERS=" host_crash_markers
    print "FATAL_RUNTIME_MARKERS=" fatal_runtime_markers
}
