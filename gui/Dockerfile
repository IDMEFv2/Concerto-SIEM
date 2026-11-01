FROM registry.fedoraproject.org/fedora-minimal:37

RUN microdnf -y update && microdnf -y install postgresql diffutils patch vim prewikka preludedb-pgsql python-kafka git gettext python3-devel python3-configargparse python3-babel python3-lesscpy python3-setuptools python3-pytzdata && microdnf clean all

WORKDIR /concerto

RUN git clone https://github.com/IDMEFv2/Concerto-MicroMap-Plugin.git

WORKDIR /concerto/Concerto-MicroMap-Plugin/prewikka_apps_micro_map

RUN python setup.py install

WORKDIR /concerto

RUN git clone https://github.com/IDMEFv2/Concerto-MacroMap-Plugin.git

WORKDIR /concerto/Concerto-MacroMap-Plugin/prewikka_apps_macro_map

RUN python setup.py install

WORKDIR /concerto

RUN git clone https://github.com/IDMEFv2/Concerto-SIEM-GUI.git

WORKDIR /concerto/Concerto-SIEM-GUI

RUN python setup.py install

RUN ln -s /usr/lib/python3.11/site-packages/pytzdata/zoneinfo /usr/share/zoneinfo

ENTRYPOINT ["/entrypoint.sh"]
