#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>

// Small helpers that need Qt's C++ side: rendering a typed signature to a
// transparent PNG without a live scene, and reading image dimensions.
class PdfxUtil : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit PdfxUtil(QObject *parent = nullptr) : QObject(parent) {}
    Q_INVOKABLE QString renderTypedSignature(const QString &text, const QString &fontFile, const QString &outPath, const QString &color = QStringLiteral("#111111"));
    Q_INVOKABLE QVariantMap imageInfo(const QString &path) const;
    Q_INVOKABLE QString fontFamilyFor(const QString &fontFile);
    // Crops a PNG to its non-transparent pixels plus padding. Returns an error string or "".
    Q_INVOKABLE QString trimTransparent(const QString &path, int padding = 24);
};
