#include <QQmlEngine>
#include <QQmlEngineExtensionPlugin>
#include "pageimageprovider.h"

extern void qml_register_types_Pdfx();

class PdfxPlugin : public QQmlEngineExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)
public:
    PdfxPlugin(QObject *parent = nullptr) : QQmlEngineExtensionPlugin(parent)
    {
        volatile auto registration = &qml_register_types_Pdfx;
        Q_UNUSED(registration);
    }
    void initializeEngine(QQmlEngine *engine, const char *uri) override
    {
        Q_UNUSED(uri);
        engine->addImageProvider(QStringLiteral("pdfx"), new PageImageProvider);
    }
};

#include "plugin.moc"
