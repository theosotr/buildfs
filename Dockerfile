ARG IMAGE_NAME=debian:stretch
FROM ${IMAGE_NAME}
ARG GRADLE
ARG SBUILD
ARG MKCHECK


RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y \
    wget \
    strace \
    python3-pip \
    opam \
    sudo \
    m4 \
    vim \
    build-essential \
    curl \
    zip \
    bc \
    make

ENV HOME /home/buildfs
ENV PROJECT_SRC=${HOME}/buildfs_src \
    MKCHECK_SRC=${HOME}/mkcheck_src \
    SCRIPTS_DIR=/usr/local/bin


# Create the buildfs user.
RUN useradd -ms /bin/bash buildfs && \
    echo buildfs:buildfs | chpasswd && \
    cp /etc/sudoers /etc/sudoers.bak && \
    echo 'buildfs ALL=(root) NOPASSWD:ALL' >> /etc/sudoers
USER buildfs
WORKDIR ${HOME}


WORKDIR ${HOME}
# Setup OCaml compiler
RUN if [ "$SBUILD" = "yes" ]; then \
        opam init -y --disable-sandboxing && \
        eval `opam config env` && \
        opam switch create 4.07.0 ; \
    else \
        opam init -y && \
        eval `opam config env` && \
        opam switch 4.07.0 \
    ; fi


# Install OCaml packages
RUN eval `opam config env` && \
    opam install -y ppx_jane core yojson dune ounit fd-send-recv fpath

RUN sudo apt install procps -y

USER root
WORKDIR /root

# Install Kotlin
RUN echo $GRADLE
RUN if [ "$GRADLE" = "yes" ]; then apt install -y gradle openjdk-8-jdk; fi
RUN if [ "$GRADLE" = "yes" ]; then wget -O sdk.install.sh "https://get.sdkman.io" && bash sdk.install.sh; fi
RUN if [ "$GRADLE" = "yes" ]; then bash -c "source ~/.sdkman/bin/sdkman-init.sh && sdk install kotlin"; fi

# Install Android SDK.
ENV ANDROID_TOOLS=https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip
RUN if [ "$GRADLE" = "yes" ]; then apt update && apt install -y android-sdk; fi

# Accept licenses.
WORKDIR /root
RUN if [ "$GRADLE" = "yes" ]; then update-java-alternatives --set java-1.8.0-openjdk-amd64; fi
RUN if [ "$GRADLE" = "yes" ]; then wget $ANDROID_TOOLS -O tools.zip && unzip tools.zip; fi
RUN if [ "$GRADLE" = "yes" ]; then yes | /root/tools/bin/sdkmanager --licenses && \
  cp -r /root/licenses /usr/lib/android-sdk; fi

# Copy necessary files
USER buildfs
WORKDIR $HOME

RUN if [ "$GRADLE" = "yes"  ]; then mkdir gradle-instrumentation; fi
ENV ANDROID_SDK_ROOT=/usr/lib/android-sdk
ENV ANDROID_HOME=/usr/lib/android-sdk

# Set the appropriate permissions.
RUN if [ "$GRADLE" = "yes"  ]; then sudo chown -R buildfs:buildfs ${ANDROID_SDK_ROOT}; fi

COPY ./gradle-instrumentation ${HOME}/gradle-instrumentation

# Build Gradle plugin
WORKDIR $HOME/gradle-instrumentation
RUN if [ "$GRADLE" = "yes"  ]; then gradle build; fi

# Set the environement variable pointint to the Gradle plugin.
ENV ANDROID_SDK_ROOT=/usr/lib/android-sdk
ENV ANDROID_HOME=/usr/lib/android-sdk
ENV PLUGIN_JAR_DIR=$HOME/gradle-instrumentation/build/libs/

# sbuild
USER root
WORKDIR /root

RUN if [ "$SBUILD" = "yes"  ]; then apt install -y sbuild schroot debootstrap; fi

# INSTALL sbuild
RUN if [ "$SBUILD" = "yes"  ]; then sbuild-adduser root; fi
RUN if [ "$SBUILD" = "yes"  ]; then sbuild-adduser buildfs; fi
RUN if [ "$SBUILD" = "yes"  ]; then sbuild-createchroot --include=eatmydata,ccache,gnupg stable /srv/chroot/stable-amd64-sbuild http://deb.debian.org/debian; fi
RUN if [ "$SBUILD" = "yes"  ]; then sbuild-createchroot --include=eatmydata,ccache,gnupg stretch /srv/chroot/stretch-amd64-sbuild http://deb.debian.org/debian; fi

# DIRECTORY TO SAVE STATS
RUN if [ "$SBUILD" = "yes"  ]; then mkdir -p /var/log/sbuild/stats; fi
RUN if [ "$SBUILD" = "yes"  ]; then chown -R buildfs /var/log/sbuild; fi

USER buildfs
WORKDIR ${HOME}
# Add project files
# Setup the environment
ADD ./entrypoint ${SCRIPTS_DIR}
ADD ./make-instrumentation ${SCRIPTS_DIR}

RUN mkdir ${PROJECT_SRC}
ADD ./src ${PROJECT_SRC}/src
ADD ./dune-project ${PROJECT_SRC}/dune-project
ADD ./buildfs.opam ${PROJECT_SRC}/buildfs.opam

RUN sudo chown -R buildfs:buildfs ${PROJECT_SRC}
RUN echo "eval `opam config env`" >> ${HOME}/.bashrc

# Build buildfs
WORKDIR ${PROJECT_SRC}
RUN eval `opam config env` && dune build -p buildfs && dune install

USER buildfs
WORKDIR ${HOME}

# mkcheck
ADD ./mkcheck-sbuild/ mkcheck-sbuild/
RUN if [ "$MKCHECK" = "yes" ]; then sudo cp ./mkcheck-sbuild/fuzz_test /usr/local/bin/ ;fi
RUN if [ "$MKCHECK" = "yes" ]; then sudo cp ./mkcheck-sbuild/run-mkcheck /usr/local/bin/ ;fi
RUN if [ "$MKCHECK" = "yes" ]; then mkdir ${MKCHECK_SRC} ;fi
RUN if [ "$MKCHECK" = "yes" ]; then cd ${MKCHECK_SRC} ;fi
RUN if [ "$MKCHECK" = "yes" ]; then sudo apt-get install -y cmake clang libboost-all-dev bc python-pip python-yaml ;fi
RUN if [ "$MKCHECK" = "yes" ]; then pip install requests beautifulsoup4 ;fi
RUN if [ "$MKCHECK" = "yes" ]; then git clone https://github.com/nandor/mkcheck ;fi
RUN if [ "$MKCHECK" = "yes" ]; then cd mkcheck && git checkout 09f520ce5ceceb42c2371d9df6f83b045223f260 && \
    cp ../mkcheck-sbuild/syscall.cpp mkcheck/syscall.cpp  && \
    mkdir Release && cd Release && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++ && \
    make && sudo install ./mkcheck /usr/local/bin/ ;fi

USER buildfs
WORKDIR ${HOME}

# sbuild configuration files
RUN mkdir buildfs-sbuild
ADD ./buildfs-sbuild buildfs-sbuild

USER root
RUN if [ "$SBUILD" = "yes"  ]; then cp ./buildfs-sbuild/sbuildrc /root/.sbuildrc; fi
RUN if [ "$SBUILD" = "yes"  ]; then cp ./buildfs-sbuild/fstab /etc/schroot/sbuild/fstab; fi
RUN if [ "$SBUILD" = "yes"  ]; then cp ./buildfs-sbuild/run-buildfs /usr/local/bin/; fi
USER buildfs
RUN if [ "$SBUILD" = "yes"  ]; then cp ./buildfs-sbuild/sbuildrc /home/buildfs/.sbuildrc; fi


ENTRYPOINT ["process-project.sh"]
