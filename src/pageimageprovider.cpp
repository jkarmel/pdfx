#include "pageimageprovider.h"
#include "documentstate.h"

#include <QImage>
#include <QMutexLocker>
#include <QRunnable>
#include <QThreadPool>
#include <QtMath>

namespace {

class PageResponse : public QQuickImageResponse, public QRunnable {
public:
    PageResponse(QString id, QSize requestedSize) : m_id(std::move(id)), m_requestedSize(requestedSize)
    {
        setAutoDelete(false);
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QString errorString() const override { return m_error; }

    void run() override
    {
        render();
        emit finished();
    }

private:
    void render()
    {
        const QStringList parts = m_id.split(QLatin1Char('/'));
        if (parts.size() < 2) { m_error = QStringLiteral("bad page id"); return; }
        auto state = DocumentRegistry::instance().lookup(parts.at(0));
        if (!state) { m_error = QStringLiteral("document closed"); return; }
        const int pageIndex = parts.at(1).toInt();

        QMutexLocker lock(&state->mutex);
        if (!state->document) { m_error = QStringLiteral("document closed"); return; }
        auto page = state->document->page(pageIndex);
        if (!page) { m_error = QStringLiteral("no such page"); return; }
        const QSizeF pageSize = page->pageSizeF();
        double dpi = 72.0;
        if (m_requestedSize.width() > 0 && pageSize.width() > 0)
            dpi = 72.0 * m_requestedSize.width() / pageSize.width();
        else if (m_requestedSize.height() > 0 && pageSize.height() > 0)
            dpi = 72.0 * m_requestedSize.height() / pageSize.height();
        dpi = qBound(18.0, dpi, 72.0 * 6.0);
        m_image = page->renderToImage(dpi, dpi);
        if (m_image.isNull()) m_error = QStringLiteral("render failed");
    }

    QString m_id;
    QSize m_requestedSize;
    QImage m_image;
    QString m_error;
};

} // namespace

QQuickImageResponse *PageImageProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    auto *response = new PageResponse(id, requestedSize);
    QThreadPool::globalInstance()->start(response);
    return response;
}
