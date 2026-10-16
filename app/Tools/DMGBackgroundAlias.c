#include <CoreServices/CoreServices.h>
#include <stdio.h>
#include <string.h>

// Build-time metadata only. No UI automation or application runtime code.
// create: write a native relative alias for Finder's backgroundImageAlias.
// check: resolve that alias without UI or mounting another volume.
static int fail(const char *what, OSStatus status) {
    fprintf(stderr, "%s (%d)\n", what, (int)status);
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 5 || (strcmp(argv[1], "create") && strcmp(argv[1], "check"))) {
        fputs("Usage: DMGBackgroundAlias create|check <DS_Store> <background> <alias-data>\n", stderr);
        return 2;
    }
    FSRef base, target, resolved;
    OSStatus status = FSPathMakeRef((const UInt8 *)argv[2], &base, NULL);
    if (status) return fail("Cannot reference layout file", status);
    status = FSPathMakeRef((const UInt8 *)argv[3], &target, NULL);
    if (status) return fail("Cannot reference background file", status);
    AliasHandle alias = NULL;
    if (!strcmp(argv[1], "create")) {
        status = FSNewAlias(&base, &target, &alias);
        if (status) return fail("Cannot create background alias", status);
        Size size = GetHandleSize((Handle)alias);
        FILE *output = fopen(argv[4], "wbx");
        if (!output) { DisposeHandle((Handle)alias); perror("alias output"); return 1; }
        size_t written = fwrite(*alias, 1, (size_t)size, output);
        int closed = fclose(output);
        DisposeHandle((Handle)alias);
        return written == (size_t)size && !closed ? 0 : fail("Cannot save alias", -1);
    }
    FILE *input = fopen(argv[4], "rb");
    if (!input) { perror("alias input"); return 1; }
    if (fseek(input, 0, SEEK_END)) { fclose(input); return 1; }
    long size = ftell(input);
    if (size <= 0 || size > 65536 || fseek(input, 0, SEEK_SET)) { fclose(input); return 1; }
    alias = (AliasHandle)NewHandle(size);
    if (!alias) { fclose(input); return 1; }
    size_t read = fread(*alias, 1, (size_t)size, input);
    fclose(input);
    if (read != (size_t)size) { DisposeHandle((Handle)alias); return 1; }
    Boolean changed = false;
    status = FSResolveAliasWithMountFlags(&base, alias, &resolved, &changed, kARMNoUI);
    DisposeHandle((Handle)alias);
    if (status) return fail("Cannot resolve background alias", status);
    if (FSCompareFSRefs(&resolved, &target)) return fail("Alias resolves to a different file", -1);
    puts("Background alias resolves to the image's background file.");
    return 0;
}
