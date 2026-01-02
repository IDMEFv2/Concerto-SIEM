FROM jertel/elastalert2:2.27.0
USER root
RUN apt update && apt -y upgrade && apt -y install git && rm -rf /var/lib/apt/lists/* && apt -y autoremove
RUN pip install --no-cache-dir sigma-cli kafka-python
WORKDIR /opt
RUN git clone https://github.com/SigmaHQ/pySigma-backend-elasticsearch.git
WORKDIR /opt/pySigma-backend-elasticsearch
COPY ./*.patch /opt/
RUN for i in /opt/*.patch; do patch -p1 < "$i"; done
RUN pip install .

COPY ./concerto_correlator.sh /opt/
RUN chmod +x /opt/concerto_correlator.sh
RUN mkdir /opt/elastalert/rules

COPY ./elastalert_concerto /usr/local/lib/python3.14/site-packages/elastalert/elastalert_concerto

RUN chown -R elastalert: /opt/elastalert
WORKDIR /opt/elastalert
USER elastalert
ENTRYPOINT ["/opt/concerto_correlator.sh"]
