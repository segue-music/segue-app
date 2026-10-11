package io.github.mateusguilherme.segue

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

// The covers of the music the app lists to Android Auto (lib/player/browse_tree.dart). Android Auto,
// another app, takes a cover only as a content:// address: it can't read the app's files, and the
// media server's address of a cover carries the login. Each is a file the app downloads to its cache
// (segue-covers, as for the media controls), served here, to read, by its name:
// content://io.github.mateusguilherme.segue.covers/<name>.jpg. The app downloads them as it lists
// them, written whole under another name and then renamed, so a file here is never half there; one
// asked for before it has come is waited for a while, Android Auto showing that it loads.
class CoverProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val name = uri.lastPathSegment

        if (mode != "r" || name == null || !NAME.matches(name)) {
            throw FileNotFoundException(uri.toString())
        }

        val file = File(File(context!!.cacheDir, DIRECTORY), name)
        val until = System.currentTimeMillis() + WAIT_MILLISECONDS

        // A binder thread's, which can wait: Android Auto asks on one of its own.
        while (!file.exists() && System.currentTimeMillis() < until) {
            Thread.sleep(POLL_MILLISECONDS)
        }

        if (!file.exists()) {
            throw FileNotFoundException(uri.toString())
        }

        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "image/jpeg"

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = 0

    private companion object {
        /** In the app's cache, as Dart's getTemporaryDirectory gives it on Android. */
        const val DIRECTORY = "segue-covers"

        /** A cover's file, as lib/player/media_controls.dart names it: no other path. */
        val NAME = Regex("[A-Za-z0-9_-]+\\.jpg")

        const val WAIT_MILLISECONDS = 10_000L
        const val POLL_MILLISECONDS = 100L
    }
}
