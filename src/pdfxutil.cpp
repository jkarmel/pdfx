#include "pdfxutil.h"

#include <QFontDatabase>
#include <QFontMetricsF>
#include <QHash>
#include <QImage>
#include <QPainter>

namespace {
QHash<QString, QString> &families()
{
    static QHash<QString, QString> map;
    return map;
}
}

QString PdfxUtil::fontFamilyFor(const QString &fontFile)
{
    QString path = fontFile;
    if (path.startsWith(QLatin1String("file://"))) path = path.mid(7);
    if (families().contains(path)) return families().value(path);
    const int id = QFontDatabase::addApplicationFont(path);
    const QStringList found = id >= 0 ? QFontDatabase::applicationFontFamilies(id) : QStringList();
    const QString family = found.isEmpty() ? QString() : found.first();
    families().insert(path, family);
    return family;
}

QString PdfxUtil::renderTypedSignature(const QString &text, const QString &fontFile, const QString &outPath, const QString &color)
{
    const QString family = fontFamilyFor(fontFile);
    if (family.isEmpty()) return QStringLiteral("could not load font %1").arg(fontFile);
    QFont font(family);
    font.setPixelSize(180);
    const QFontMetricsF metrics(font);
    const QRectF bounds = metrics.boundingRect(text);
    const int pad = 40;
    QImage image(int(std::ceil(bounds.width())) + pad * 2, int(std::ceil(metrics.height())) + pad * 2, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::TextAntialiasing, true);
    painter.setFont(font);
    painter.setPen(QColor(color));
    painter.drawText(QPointF(pad - bounds.left(), pad + metrics.ascent()), text);
    painter.end();
    return image.save(outPath, "PNG") ? QString() : QStringLiteral("could not write %1").arg(outPath);
}

QVariantMap PdfxUtil::imageInfo(const QString &path) const
{
    QImage image(path);
    if (image.isNull()) return {};
    return {{QStringLiteral("width"), image.width()}, {QStringLiteral("height"), image.height()}};
}

QString PdfxUtil::trimTransparent(const QString &path, int padding)
{
    QImage image(path);
    if (image.isNull()) return QStringLiteral("could not read %1").arg(path);
    image = image.convertToFormat(QImage::Format_ARGB32);
    int minX = image.width(), minY = image.height(), maxX = -1, maxY = -1;
    for (int y = 0; y < image.height(); ++y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(row[x]) > 8) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }
    if (maxX < 0) return QStringLiteral("the signature is empty");
    const QRect bounds(minX, minY, maxX - minX + 1, maxY - minY + 1);
    QImage out(bounds.width() + padding * 2, bounds.height() + padding * 2, QImage::Format_ARGB32);
    out.fill(Qt::transparent);
    QPainter painter(&out);
    painter.drawImage(QPoint(padding, padding), image, bounds);
    painter.end();
    return out.save(path, "PNG") ? QString() : QStringLiteral("could not write %1").arg(path);
}
