#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QSizeF>
#include <QVariantList>
#include <memory>
#include "documentstate.h"

// One loaded PDF. Exposed to QML as `PdfDoc`. Pages render through the
// `image://pdfx/<key>/<page>/<revision>` provider; `revision` bumps after
// every edit so bound Images refetch.
class PdfDoc : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(QString key READ key NOTIFY pathChanged)
    Q_PROPERTY(int pageCount READ pageCount NOTIFY pathChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(bool modified READ modified NOTIFY modifiedChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QVariantList fields READ fields NOTIFY fieldsChanged)
    Q_PROPERTY(QVariantList pageSizes READ pageSizes NOTIFY pathChanged)
    // Number of signatures/text items placed since the last load or save.
    Q_PROPERTY(int addedCount READ addedAnnotationCount NOTIFY revisionChanged)

public:
    explicit PdfDoc(QObject *parent = nullptr);
    ~PdfDoc() override;

    QString path() const { return m_path; }
    QString key() const { return m_key; }
    int pageCount() const { return m_pageCount; }
    int revision() const { return m_revision; }
    bool modified() const { return m_modified; }
    QString error() const { return m_error; }
    QVariantList fields() const { return m_fields; }
    QVariantList pageSizes() const { return m_pageSizes; }

    Q_INVOKABLE bool load(const QString &path);
    // Field values: text for text fields, "true"/"false" for check boxes and
    // radios, an option label (or index) for choices.
    Q_INVOKABLE bool setField(const QString &nameOrId, const QString &value);
    Q_INVOKABLE QVariantMap field(const QString &nameOrId) const;
    // Rects are normalized to the page: (0,0) top-left, (1,1) bottom-right.
    Q_INVOKABLE bool addImage(int page, const QRectF &rect, const QString &imagePath);
    Q_INVOKABLE bool addText(int page, const QRectF &rect, const QString &text, double pointSize, const QString &fontFamily);
    // Removes the most recently added annotation (stamp or text) on a page.
    Q_INVOKABLE bool removeLastAnnotation();
    Q_INVOKABLE int addedAnnotationCount() const { return int(m_added.size()); }
    Q_INVOKABLE QVariantList addedAnnotations() const;
    // Saves with changes. Empty path saves in place (atomically via a temp file).
    Q_INVOKABLE bool save(const QString &path = QString());
    Q_INVOKABLE QString imageSource(int page) const;
    Q_INVOKABLE QVariantMap imageInfo(const QString &imagePath) const;

signals:
    void pathChanged();
    void revisionChanged();
    void modifiedChanged();
    void errorChanged();
    void fieldsChanged();

private:
    struct Added { int page; QString uniqueName; QString kind; QRectF rect; };
    void setError(const QString &error);
    void bump(bool modified);
    void refreshFields();   // caller must NOT hold the mutex
    QVariantList collectFieldsLocked();
    std::unique_ptr<Poppler::FormField> findFieldLocked(const QString &nameOrId, int *pageOut);
    bool reloadFrom(const QString &path);

    std::shared_ptr<DocumentState> m_state;
    QString m_path;
    QString m_key;
    int m_pageCount = 0;
    int m_revision = 0;
    bool m_modified = false;
    QString m_error;
    QVariantList m_fields;
    QVariantList m_pageSizes;
    std::vector<Added> m_added;
    quint64 m_annotationSerial = 0;
};
