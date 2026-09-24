#pragma once

#include <QQuickAsyncImageProvider>

// image://pdfx/<docKey>/<page>/<revision>
// The requested size is the target pixel size of the page image; the page is
// rendered at the resolution that fits it (aspect preserved).
class PageImageProvider : public QQuickAsyncImageProvider {
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};
