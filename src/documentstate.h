#pragma once

#include <QMutex>
#include <QString>
#include <memory>
#include <poppler-qt6.h>

// Shared between PdfDoc (owner) and the render jobs on the thread pool.
// Every touch of the Poppler document goes through `mutex`.
struct DocumentState {
    QMutex mutex;
    std::unique_ptr<Poppler::Document> document;
    QString path;
};

class DocumentRegistry {
public:
    static DocumentRegistry &instance();
    QString add(const std::shared_ptr<DocumentState> &state);
    void remove(const QString &key);
    std::shared_ptr<DocumentState> lookup(const QString &key);
private:
    QMutex m_mutex;
    QHash<QString, std::weak_ptr<DocumentState>> m_entries;
    quint64 m_next = 1;
};
