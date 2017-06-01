FROM concourse/buildroot:hg

RUN hg clone https://www.mercurial-scm.org/repo/evolve -r mercurial-3.9 && (cd evolve && python setup.py install) && rm -r evolve
COPY hgrc /etc/mercurial/hgrc

RUN mkdir -p /opt/resource
ADD hgresource/hgresource /opt/resource
ADD assets/askpass.sh /opt/resource
RUN chmod +x /opt/resource/*
RUN ln -s /opt/resource/hgresource /opt/resource/in; ln -s /opt/resource/hgresource /opt/resource/out; ln -s /opt/resource/hgresource /opt/resource/check
