#include "pdfdoc.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QImage>
#include <QMutexLocker>
#include <QSaveFile>
#include <QTemporaryFile>
#include <QUuid>
#include <poppler-annotation.h>
#include <poppler-form.h>

namespace {

QString fieldTypeName(const Poppler::FormField *field)
{
    switch (field->type()) {
    case Poppler::FormField::FormButton: {
        auto *button = static_cast<const Poppler::FormFieldButton *>(field);
        switch (button->buttonType()) {
        case Poppler::FormFieldButton::Push: return QStringLiteral("button");
        case Poppler::FormFieldButton::CheckBox: return QStringLiteral("checkbox");
        case Poppler::FormFieldButton::Radio: return QStringLiteral("radio");
        }
        return QStringLiteral("button");
    }
    case Poppler::FormField::FormText: return QStringLiteral("text");
    case Poppler::FormField::FormChoice: return QStringLiteral("choice");
    case Poppler::FormField::FormSignature: return QStringLiteral("signature");
    }
    return QStringLiteral("unknown");
}

QString fieldValue(const Poppler::FormField *field)
{
    switch (field->type()) {
    case Poppler::FormField::FormButton:
        return static_cast<const Poppler::FormFieldButton *>(field)->state() ? QStringLiteral("true") : QStringLiteral("false");
    case Poppler::FormField::FormText:
        return static_cast<const Poppler::FormFieldText *>(field)->text();
    case Poppler::FormField::FormChoice: {
        auto *choice = static_cast<const Poppler::FormFieldChoice *>(field);
        if (choice->isEditable() && !choice->editChoice().isEmpty())
            return choice->editChoice();
        QStringList picked;
        const QStringList options = choice->choices();
        for (int index : choice->currentChoices())
            if (index >= 0 && index < options.size()) picked << options.at(index);
        return picked.join(QStringLiteral(", "));
    }
    case Poppler::FormField::FormSignature:
        return QString();
    }
    return QString();
}

bool truthy(const QString &value)
{
    const QString v = value.trimmed().toLower();
    return v == QLatin1String("true") || v == QLatin1String("1") || v == QLatin1String("yes")
        || v == QLatin1String("on") || v == QLatin1String("x") || v == QLatin1String("checked");
}

} // namespace

PdfDoc::PdfDoc(QObject *parent) : QObject(parent) {}

PdfDoc::~PdfDoc()
{
    if (!m_key.isEmpty()) DocumentRegistry::instance().remove(m_key);
}

void PdfDoc::setError(const QString &error)
{
    if (m_error == error) return;
    m_error = error;
    emit errorChanged();
}

void PdfDoc::bump(bool modified)
{
    m_revision++;
    emit revisionChanged();
    if (modified != m_modified) {
        m_modified = modified;
        emit modifiedChanged();
    }
}

bool PdfDoc::load(const QString &path)
{
    m_added.clear();
    if (!reloadFrom(path)) return false;
    m_modified = false;
    emit modifiedChanged();
    return true;
}

bool PdfDoc::reloadFrom(const QString &path)
{
    auto document = Poppler::Document::load(path);
    if (!document) {
        setError(QStringLiteral("Could not open %1").arg(path));
        return false;
    }
    if (document->isLocked()) {
        setError(QStringLiteral("%1 is password protected").arg(path));
        return false;
    }
    document->setRenderHint(Poppler::Document::Antialiasing, true);
    document->setRenderHint(Poppler::Document::TextAntialiasing, true);
    document->setRenderHint(Poppler::Document::TextHinting, true);
    document->setRenderHint(Poppler::Document::TextSlightHinting, true);
    document->setRenderHint(Poppler::Document::ThinLineSolid, true);

    auto state = std::make_shared<DocumentState>();
    state->document = std::move(document);
    state->path = path;

    QVariantList sizes;
    const int count = state->document->numPages();
    for (int i = 0; i < count; ++i) {
        auto page = state->document->page(i);
        const QSizeF size = page ? page->pageSizeF() : QSizeF(612, 792);
        sizes << QVariantMap{{QStringLiteral("width"), size.width()}, {QStringLiteral("height"), size.height()}};
    }

    if (!m_key.isEmpty()) DocumentRegistry::instance().remove(m_key);
    m_state = state;
    m_key = DocumentRegistry::instance().add(state);
    m_path = path;
    m_pageCount = count;
    m_pageSizes = sizes;
    setError(QString());
    emit pathChanged();
    refreshFields();
    bump(m_modified);
    return true;
}

QVariantList PdfDoc::collectFieldsLocked()
{
    QVariantList out;
    if (!m_state || !m_state->document) return out;
    for (int pageIndex = 0; pageIndex < m_pageCount; ++pageIndex) {
        auto page = m_state->document->page(pageIndex);
        if (!page) continue;
        for (const auto &field : page->formFields()) {
            if (!field) continue;
            QVariantMap entry;
            entry[QStringLiteral("id")] = field->id();
            entry[QStringLiteral("name")] = field->fullyQualifiedName().isEmpty() ? field->name() : field->fullyQualifiedName();
            entry[QStringLiteral("shortName")] = field->name();
            entry[QStringLiteral("type")] = fieldTypeName(field.get());
            entry[QStringLiteral("page")] = pageIndex;
            const QRectF rect = field->rect();
            entry[QStringLiteral("x")] = rect.x();
            entry[QStringLiteral("y")] = rect.y();
            entry[QStringLiteral("width")] = rect.width();
            entry[QStringLiteral("height")] = rect.height();
            entry[QStringLiteral("readOnly")] = field->isReadOnly();
            entry[QStringLiteral("visible")] = field->isVisible();
            entry[QStringLiteral("value")] = fieldValue(field.get());
            if (field->type() == Poppler::FormField::FormChoice) {
                auto *choice = static_cast<const Poppler::FormFieldChoice *>(field.get());
                entry[QStringLiteral("choices")] = choice->choices();
                entry[QStringLiteral("editable")] = choice->isEditable();
                entry[QStringLiteral("multiSelect")] = choice->multiSelect();
            }
            if (field->type() == Poppler::FormField::FormText) {
                auto *text = static_cast<const Poppler::FormFieldText *>(field.get());
                entry[QStringLiteral("multiline")] = text->textType() == Poppler::FormFieldText::Multiline;
                entry[QStringLiteral("maxLength")] = text->maximumLength();
            }
            out << entry;
        }
    }
    return out;
}

void PdfDoc::refreshFields()
{
    QVariantList fields;
    if (m_state) {
        QMutexLocker lock(&m_state->mutex);
        fields = collectFieldsLocked();
    }
    m_fields = fields;
    emit fieldsChanged();
}

std::unique_ptr<Poppler::FormField> PdfDoc::findFieldLocked(const QString &nameOrId, int *pageOut)
{
    if (!m_state || !m_state->document) return nullptr;
    bool isNumber = false;
    const int wantedId = nameOrId.toInt(&isNumber);
    std::unique_ptr<Poppler::FormField> byShortName;
    int shortNamePage = -1;
    for (int pageIndex = 0; pageIndex < m_pageCount; ++pageIndex) {
        auto page = m_state->document->page(pageIndex);
        if (!page) continue;
        for (auto &field : page->formFields()) {
            if (!field) continue;
            if ((isNumber && field->id() == wantedId) || field->fullyQualifiedName() == nameOrId) {
                if (pageOut) *pageOut = pageIndex;
                return std::move(field);
            }
            if (!byShortName && field->name() == nameOrId) {
                byShortName = std::move(field);
                shortNamePage = pageIndex;
            }
        }
    }
    if (byShortName && pageOut) *pageOut = shortNamePage;
    return byShortName;
}

QVariantMap PdfDoc::field(const QString &nameOrId) const
{
    bool isNumber = false;
    const int wantedId = nameOrId.toInt(&isNumber);
    for (const QVariant &entry : m_fields) {
        const QVariantMap map = entry.toMap();
        if ((isNumber && map.value(QStringLiteral("id")).toInt() == wantedId)
            || map.value(QStringLiteral("name")).toString() == nameOrId
            || map.value(QStringLiteral("shortName")).toString() == nameOrId)
            return map;
    }
    return {};
}

bool PdfDoc::setField(const QString &nameOrId, const QString &value)
{
    if (!m_state) return false;
    bool ok = false;
    {
        QMutexLocker lock(&m_state->mutex);
        int page = -1;
        auto field = findFieldLocked(nameOrId, &page);
        if (!field) {
            setError(QStringLiteral("No form field named %1").arg(nameOrId));
            return false;
        }
        if (field->isReadOnly()) {
            setError(QStringLiteral("Field %1 is read-only").arg(nameOrId));
            return false;
        }
        switch (field->type()) {
        case Poppler::FormField::FormText:
            static_cast<Poppler::FormFieldText *>(field.get())->setText(value);
            ok = true;
            break;
        case Poppler::FormField::FormButton: {
            auto *button = static_cast<Poppler::FormFieldButton *>(field.get());
            if (button->buttonType() == Poppler::FormFieldButton::Push) {
                setError(QStringLiteral("Field %1 is a push button").arg(nameOrId));
                return false;
            }
            button->setState(truthy(value));
            ok = true;
            break;
        }
        case Poppler::FormField::FormChoice: {
            auto *choice = static_cast<Poppler::FormFieldChoice *>(field.get());
            const QStringList options = choice->choices();
            QList<int> picked;
            for (const QString &part : value.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
                const QString wanted = part.trimmed();
                int index = options.indexOf(wanted);
                if (index < 0) {
                    bool numeric = false;
                    const int n = wanted.toInt(&numeric);
                    if (numeric && n >= 0 && n < options.size()) index = n;
                }
                if (index < 0) {
                    for (int i = 0; i < options.size() && index < 0; ++i)
                        if (options.at(i).compare(wanted, Qt::CaseInsensitive) == 0) index = i;
                }
                if (index >= 0) picked << index;
            }
            if (picked.isEmpty() && choice->isEditable()) {
                choice->setEditChoice(value);
                ok = true;
            } else if (!picked.isEmpty()) {
                choice->setCurrentChoices(choice->multiSelect() ? picked : QList<int>{picked.first()});
                ok = true;
            } else {
                setError(QStringLiteral("%1 is not an option of %2").arg(value, nameOrId));
                return false;
            }
            break;
        }
        case Poppler::FormField::FormSignature:
            setError(QStringLiteral("Field %1 is a digital signature field; place a visual signature instead").arg(nameOrId));
            return false;
        }
    }
    if (ok) {
        setError(QString());
        refreshFields();
        bump(true);
    }
    return ok;
}

bool PdfDoc::addImage(int pageIndex, const QRectF &rect, const QString &imagePath)
{
    if (!m_state) return false;
    QImage image(imagePath);
    if (image.isNull()) {
        setError(QStringLiteral("Could not read image %1").arg(imagePath));
        return false;
    }
    if (image.format() != QImage::Format_ARGB32) image = image.convertToFormat(QImage::Format_ARGB32);
    const QString name = QStringLiteral("pdfx-%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    {
        QMutexLocker lock(&m_state->mutex);
        auto page = m_state->document->page(pageIndex);
        if (!page) {
            setError(QStringLiteral("No page %1").arg(pageIndex + 1));
            return false;
        }
        auto *stamp = new Poppler::StampAnnotation();
        stamp->setStampCustomImage(image);
        stamp->setBoundary(rect);
        stamp->setUniqueName(name);
        stamp->setAuthor(QStringLiteral("pdfx"));
        stamp->setCreationDate(QDateTime::currentDateTime());
        stamp->setModificationDate(QDateTime::currentDateTime());
        page->addAnnotation(stamp);
        delete stamp;
    }
    m_added.push_back({pageIndex, name, QStringLiteral("image"), rect});
    setError(QString());
    bump(true);
    return true;
}

bool PdfDoc::addText(int pageIndex, const QRectF &rect, const QString &text, double pointSize, const QString &fontFamily)
{
    if (!m_state) return false;
    const QString name = QStringLiteral("pdfx-%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    {
        QMutexLocker lock(&m_state->mutex);
        auto page = m_state->document->page(pageIndex);
        if (!page) {
            setError(QStringLiteral("No page %1").arg(pageIndex + 1));
            return false;
        }
        auto *annotation = new Poppler::TextAnnotation(Poppler::TextAnnotation::InPlace);
        annotation->setContents(text);
        QFont font(fontFamily.isEmpty() ? QStringLiteral("Helvetica") : fontFamily);
        font.setPointSizeF(pointSize > 0 ? pointSize : 11.0);
        annotation->setTextFont(font);
        annotation->setTextColor(Qt::black);
        Poppler::Annotation::Style style;
        style.setWidth(0);
        annotation->setStyle(style);
        annotation->setBoundary(rect);
        annotation->setUniqueName(name);
        annotation->setAuthor(QStringLiteral("pdfx"));
        annotation->setCreationDate(QDateTime::currentDateTime());
        annotation->setModificationDate(QDateTime::currentDateTime());
        page->addAnnotation(annotation);
        delete annotation;
    }
    m_added.push_back({pageIndex, name, QStringLiteral("text"), rect});
    setError(QString());
    bump(true);
    return true;
}

bool PdfDoc::removeLastAnnotation()
{
    if (!m_state || m_added.empty()) return false;
    const Added last = m_added.back();
    bool removed = false;
    {
        QMutexLocker lock(&m_state->mutex);
        auto page = m_state->document->page(last.page);
        if (page) {
            for (const auto &annotation : page->annotations()) {
                if (annotation && annotation->uniqueName() == last.uniqueName) {
                    page->removeAnnotation(annotation.get());
                    removed = true;
                    break;
                }
            }
        }
    }
    m_added.pop_back();
    if (removed) bump(true);
    return removed;
}

QVariantList PdfDoc::addedAnnotations() const
{
    QVariantList out;
    for (const Added &added : m_added) {
        out << QVariantMap{{QStringLiteral("page"), added.page}, {QStringLiteral("kind"), added.kind},
                           {QStringLiteral("x"), added.rect.x()}, {QStringLiteral("y"), added.rect.y()},
                           {QStringLiteral("width"), added.rect.width()}, {QStringLiteral("height"), added.rect.height()}};
    }
    return out;
}

bool PdfDoc::save(const QString &requestedPath)
{
    if (!m_state) return false;
    const QString target = requestedPath.isEmpty() ? m_path : requestedPath;
    const QFileInfo info(target);
    QTemporaryFile temp(info.absoluteDir().filePath(QStringLiteral(".pdfx-XXXXXX.pdf")));
    temp.setAutoRemove(false);
    if (!temp.open()) {
        setError(QStringLiteral("Cannot write into %1").arg(info.absolutePath()));
        return false;
    }
    const QString tempPath = temp.fileName();
    temp.close();
    bool converted = false;
    {
        QMutexLocker lock(&m_state->mutex);
        auto converter = m_state->document->pdfConverter();
        converter->setOutputFileName(tempPath);
        converter->setPDFOptions(Poppler::PDFConverter::WithChanges);
        converted = converter->convert();
    }
    if (!converted) {
        QFile::remove(tempPath);
        setError(QStringLiteral("Poppler could not write %1").arg(target));
        return false;
    }
    // Keep the original's permissions and replace atomically.
    QFile::setPermissions(tempPath, QFile::exists(target) ? QFile(target).permissions() : (QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther));
    if (QFile::exists(target) && !QFile::remove(target)) {
        QFile::remove(tempPath);
        setError(QStringLiteral("Cannot replace %1").arg(target));
        return false;
    }
    if (!QFile::rename(tempPath, target)) {
        setError(QStringLiteral("Cannot move saved file into place at %1").arg(target));
        return false;
    }
    // Reload from disk so the in-memory document matches the file exactly.
    m_added.clear();
    if (!reloadFrom(target)) return false;
    m_modified = false;
    emit modifiedChanged();
    return true;
}

QVariantMap PdfDoc::imageInfo(const QString &imagePath) const
{
    QImage image(imagePath);
    if (image.isNull()) return {};
    return {{QStringLiteral("width"), image.width()}, {QStringLiteral("height"), image.height()}};
}

QString PdfDoc::imageSource(int page) const
{
    return QStringLiteral("image://pdfx/%1/%2/%3").arg(m_key).arg(page).arg(m_revision);
}

// ---------------------------------------------------------------- registry

DocumentRegistry &DocumentRegistry::instance()
{
    static DocumentRegistry registry;
    return registry;
}

QString DocumentRegistry::add(const std::shared_ptr<DocumentState> &state)
{
    QMutexLocker lock(&m_mutex);
    const QString key = QStringLiteral("d%1").arg(m_next++);
    m_entries.insert(key, state);
    return key;
}

void DocumentRegistry::remove(const QString &key)
{
    QMutexLocker lock(&m_mutex);
    m_entries.remove(key);
}

std::shared_ptr<DocumentState> DocumentRegistry::lookup(const QString &key)
{
    QMutexLocker lock(&m_mutex);
    return m_entries.value(key).lock();
}
