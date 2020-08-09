#! /bin/bash
#
# This is the entrypoint script for analyzing
# and detecting faults in a Gradle or Make script
# using BuildFS.

basedir=${HOME}/data
project_url=
project_verion="latest"
project_type=
build_path=
with_strace=0
iterations=1
offline=0

eval `opam config env`


while getopts "p:v:st:k:b:o" opt; do
  case "$opt" in
    p)  project_url=$OPTARG
        ;;
    v)  project_version=$OPTARG
        ;;
    t)  project_type=$OPTARG
        ;;
    s)  with_strace=1
        ;;
    k)  iterations=$OPTARG
        ;;
    b)  build_path=$OPTARG
        ;;
    o)  offline=$OPTARG
        ;;
  esac
done
shift $(($OPTIND - 1));


if [ -z $project_url ]; then
  # Run script in interactive mode for debugging purposes.
  bash
  exit 0
fi


if [ -z "$project_type" ]; then
  echo "You must specify the type of the project"
  echo "(gradle or make or sbuild or mkcheck or sbuild-mkcheck)"
  exit 1
fi


if [ "$iterations" -lt 1 ]; then
  echo "You must provide a number greater than 1"
  exit 1
fi

sudo chown buildfs:buildfs -R $basedir

function fetch_project()
{
  local project project_out project_repo version
  project_repo=$1
  project=$2
  version=$3

  project_out=$basedir/$project
  mkdir -p $project_out

  git clone "$project_repo" $HOME/$project
  if [ $? -ne 0 ]; then
    echo "Unable to clone" > $project_out/err
    return 1
  fi

  cd $project

  if [ "$version" != "latest" ]; then
    echo "Checking out to version $version..."
    # Checkout to the given version.
    git checkout $version
    if [ $? -ne 0 ]; then
      echo "Unable to checkout to given version $version" > $project_out/err
      return 1
    fi
  fi

  cd ..
  return 0
}


instrument_build_script()
{
  plugin="$PLUGIN_JAR_DIR/gradle-instrumentation.jar"
  if [ "$1" = "groovy" ]; then
    buildscript="buildscript { dependencies { classpath files('$plugin') } }\n"
    applyplug="apply plugin: 'org.fsracer.gradle.fsracer-plugin'"
    build_file="build.gradle"
  else
    buildscript="buildscript { dependencies { classpath(files(\"$plugin\")) } }\n"
    applyplug="apply(plugin=\"org.fsracer.gradle.fsracer-plugin\")"
    build_file="build.gradle.kts"
  fi
  # Heuristic: Search for file whose name is build.gradle.[kts]
  find . -regex ".*${build_file}" -type f -printf "%d %p\n" |
  sort -n |
  head -1 |
  cut -d' ' -f2 |
  xargs -i sed -i -e "1s;^;${buildscript};" -e "\$a${applyplug}" {}
  return $?
}


function build_gradle_project()
{
  local project with_strace iterations
  project=$1
  with_strace=$2
  iterations=$3

  # Enter Gradle project's directory.
  cd $HOME/$project

  if [ $with_strace -eq 1 ]; then
    instrument_build_script "groovy"
    ret_groovy=$?
    instrument_build_script "kotlin"
    ret_kotlin=$?

    if [[ $ret_groovy -ne 0 && $ret_kotlin -ne 0 ]]; then
      echo "Unable to find build.gradle file" > $basedir/$project/err
      return 1
    fi
  fi

  if [ -x $HOME/pre-script.sh ]; then
    $HOME/pre-script.sh
  fi

  gradlew=$(find . -name 'gradlew' -type f -printf "%d %p\n" |
  sort -n |
  head -1 |
  cut -d' ' -f2)

  if [ $? -ne 0 ]; then
    echo "Unable to find gradlew file" > $basedir/$project/err
    return 1
  fi

  echo $gradlew

  if [[ ! -x $gradlew ]]; then
    gradlew="sh $gradlew"
  fi

  # Run gradle for the first time to configure project and install all
  # necessary dependencies and plugins.
  eval "$gradlew tasks"
  if [ $? -ne 0 ]; then
    return 1
  fi
  eval "$gradlew --stop"
  rm -f build-result.txt


  echo $(pwd) > $basedir/$project/$project.path
  for i in {1..$iterations}; do
    if [ $with_strace -eq 1 ]; then
      echo "Building the Gradle project $project with BuildFS..."
      echo "Depending on the build, it may take some time (even hours). Bear with us..."
      buildfs gradle-build \
        -mode online \
        -build-task build \
        -trace-file $basedir/$project/$project.strace \
        -print-stats \
        -build-dir "$(pwd)" > $basedir/$project/$project.faults 2> $basedir/$project/err
			if [ ! -s $basedir/$project/err ]; then
        rm $basedir/$project/err
        # This is the build time using BuildFS...
        btime=$(cat $basedir/$project/$project.faults |
          grep -oP 'Analysis time: .*' |
          sed -r 's/Analysis time: (.*)/\1/g')
        echo $btime >> $basedir/$project/build-buildfs.times
			fi
    else
      echo "Building the Gradle project $project without BuildFS..."
      echo "Depending on the build, it may take some time (even hours). Bear with us..."
      start_time=$(date +%s.%N)
      bash -c  "./gradlew build --no-build-cache --no-parallel >out 2>&1"
      elapsed_time=$(echo "$(date +%s.%N) - $start_time" | bc)
      # Compute the time spent on build.
      printf "%.2f\n" $elapsed_time >> $basedir/$project/base-build.time
    fi
    ./gradlew clean
    ./gradlew --stop
  done
}


function build_make_project()
{
  local project with_strace iterations build_path
  project=$1
  with_strace=$2
  iterations=$3
  build_path=$4


  if [ -z "$build_path" ]; then
    path=$HOME/$project
  else
    path=$HOME/$project/$build_path
  fi

  cd $path
  echo $(pwd) > $basedir/$project/$project.path

  if [ -x $HOME/pre-script.sh ]; then
    $HOME/pre-script.sh
  fi

  if [ -f configure ]; then
    # If the project contains a configure script, we run this set up things.
    ./configure
  fi

  for i in {1..$iterations}; do
    if [ $with_strace -eq 0 ]; then
      echo "Building the Make project $project without BuildFS..."
      echo "Depending on the build, it may take some time (even hours). Bear with us..."
      start_time=$(date +%s.%N)
      make
      elapsed_time=$(echo "$(date +%s.%N) - $start_time" | bc)
      # Compute the time spent on build.
      printf "%.2f\n" $elapsed_time >> $basedir/$project/base-build.time
    else
      sed -i -r 's/make/\$\(MAKE\)/' Makefile
      echo "Building Make project $project with BuildFS..."
      echo "Depending on the build, it may take some time (even hours). Bear with us..."
      buildfs make-build \
        -mode online \
        -trace-file $basedir/$project/$project.strace \
        -print-stats \
        -build-dir "$(pwd)" > $basedir/$project/$project.faults 2> $basedir/$project/err
			if [ ! -s $basedir/$project/err ]; then
        rm $basedir/$project/err
        # This is the build time using BuildFS...
        btime=$(cat $basedir/$project/$project.faults |
          grep -oP 'Analysis time: .*' |
          sed -r 's/Analysis time: (.*)/\1/g')
        echo $btime >> $basedir/$project/build-buildfs.times
        make -pn > $basedir/$project/$project.makedb
			fi
      make clean
    fi
  done
}


function build_sbuild_project()
{
  local project with_strace iterations sbuildrc buildfs_bin
  project=$1
  with_strace=$2
  iterations=$3

  sbuildrc=/home/buildfs/.sbuildrc

  # we cannot run which buildfs during the build of image
  buildfs_bin=$(which buildfs) && sudo cp $buildfs_bin /usr/local/bin/

  echo "Building the Make sbuild project $project..."
  sed -i "s/{PROJECT}/${project}/g" $sbuildrc
  sed -i "s/{STRACE}/${with_strace}/g" $sbuildrc
  sed -i "s/{ITERATIONS}/${iterations}/g" $sbuildrc
  sbuild --apt-update --no-apt-upgrade --no-apt-distupgrade --batch \
      --stats-dir=/var/log/sbuild/stats --dist=stable $project
  sudo chown buildfs:buildfs -R $basedir
}


function build_mkcheck_project()
{
  local project with_strace iterations build_path
  project=$1
  with_strace=$2
  iterations=$3
  build_path=$4


  if [ -z "$build_path" ]; then
    path=$HOME/$project
  else
    path=$HOME/$project/$build_path
  fi

  cd $path
  echo $(pwd) > $basedir/$project/$project.path

  if [ -x $HOME/pre-script.sh ]; then
    $HOME/pre-script.sh
  fi

  if [ -f configure ]; then
    # If the project contains a configure script, we run this set up things.
    ./configure
  fi

  mkdir -p $basedir/$project/mkcheck

  for i in {1..$iterations}; do
    if [ $with_strace -eq 0 ]; then
      echo "Building the Make project $project without mkcheck..."
      echo "Depending on the build, it may take some time (even hours). Bear with us..."
      start_time=$(date +%s.%N)
      make
      elapsed_time=$(echo "$(date +%s.%N) - $start_time" | bc)
      # Compute the time spent on build.
      printf "%.2f\n" $elapsed_time >> $basedir/$project/base-build.time
    else
      echo "Building Make project $project with mkcheck..."
      echo "Depending on the build, it may take some time (even hours). Bear with us..."
      echo "
      filter_in:
              - Makefile.*
              - /usr/.*
              - /etc/.*
              - //.*
              - /lib/.*
              - /bin/.*
              - /.*/debian/.*
      " > filter.yaml
      start_time=$(date +%s.%N)
      fuzz_test --graph-path=foo.json build 2> /dev/null
      if [ $? -ne 0 ]; then
        return
      fi
      elapsed_time=$(echo "$(date +%s.%N) - $start_time" | bc)
      printf "%.2f\n" $elapsed_time > $basedir/$project/mkcheck/$project.time

      cp foo.json $basedir/$project/mkcheck/$project.json

      echo "Fuzz testing..."
      start_time=$(date +%s.%N)
      fuzz_test --graph-path=foo.json \
        --rule-path filter.yaml fuzz \
        > $basedir/$project/mkcheck/$project.fuzz 2> /dev/null
      if [ $? -ne 0 ]; then
        exit 1
      fi
      elapsed_time=$(echo "$(date +%s.%N) - $start_time" | bc)
      printf "%.2f\n" $elapsed_time >> $basedir/$project/mkcheck/$project.time

      echo "Race testing..."
      start_time=$(date +%s.%N)
      fuzz_test --graph-path=foo.json \
        --rule-path filter.yaml race \
        > $basedir/$project/mkcheck/$project.race 2> /dev/null

      if [ $? -ne 0 ]; then
        exit 1
      fi
      elapsed_time=$(echo "$(date +%s.%N) - $start_time" | bc)
      printf "%.2f\n" $elapsed_time >> $basedir/$project/mkcheck/$project.time
    fi
  done
}


function build_sbuild_mkcheck_project()
{
  local project with_strace iterations sbuildrc mkcheck_bin
  project=$1
  with_strace=$2
  iterations=$3

  sbuildrc=/home/buildfs/.sbuildrc

  mkcheck_bin=$(which mkcheck) && sudo cp $mkcheck_bin /usr/local/bin/

  echo "Building the Make sbuild project $project with mkcheck..."
  sed -i "s/'strace',/'strace',\n'libboost-all-dev',\n'python',\n'python-pip',\n'python-yaml',\n/" $sbuildrc
  sed -i "s/run-buildfs/run-mkcheck/g" $sbuildrc
  sed -i "s/{PROJECT}/${project}/g" $sbuildrc
  sed -i "s/{STRACE}/${with_strace}/g" $sbuildrc
  sed -i "s/{ITERATIONS}/${iterations}/g" $sbuildrc
  sbuild --apt-update --no-apt-upgrade --no-apt-distupgrade --batch \
      --stats-dir=/var/log/sbuild/stats --dist=stable $project
  sudo chown buildfs:buildfs -R $basedir
}


function buildfs_offline()
{
  local project iterations
  project=$1
  iterations=$2
  project_type=$3

  set +e

  echo "Offline analysis with BuildFS..."
  if [ ! -f $basedir/$project/$project.times ]; then
    for i in {1..$iterations}; do
      if [ "$project_type" = "make" ]; then
        buildfs make-build \
          -mode offline \
          -print-stats \
          -trace-file $basedir/$project/$project.strace \
          -build-db $basedir/$project/$project.makedb \
          -build-dir "$(cat $basedir/$project/$project.path)" \
        > $basedir/$project/$project.faults 2> $basedir/$project/err
      else
        buildfs gradle-build \
          -mode offline \
          -print-stats \
          -trace-file $basedir/$project/$project.strace \
          -build-dir "$(cat $basedir/$project/$project.path)" \
        > $basedir/$project/$project.faults 2> $basedir/$project/err
      fi

      if [ $? -ne 0 ]; then
        return 2
      fi

      if [ ! -s $basedir/$project/err ]; then
        rm $basedir/$project/err
        atime=$(cat $basedir/$project/$project.faults |
        grep -oP 'Analysis time: .*' |
        sed -r 's/Analysis time: (.*)/\1/g')
        fdtime=$(cat $basedir/$project/$project.faults |
        grep -oP 'Bug detection time: .*' |
        sed -r 's/Bug detection time: (.*)/\1/g')
        echo "$atime,$fdtime" >> $basedir/$project/$project.times
      fi
    done
  fi
  return 0
}


if [ "$project_type" = "sbuild" ] || [ "$project_type" = "sbuild-mkcheck" ]; then
  project_name=$project_url
else
  project_name=$(echo $project_url | sed -r 's/^https:\/\/.*\.((org)|(com)|(net))\/.*\/(.*)\.git/\5/g')
fi

if [ ! "$project_type" = "sbuild" ] && [ ! "$project_type" = "sbuild-mkcheck" ]; then
  fetch_project "$project_url" "$project_name" "$project_version"
  if [ $? -ne 0 ]; then
    echo "Couldn't fetch the project $project"
    exit 1
  fi
fi


if [ "$project_type" = "make" ]; then
  build_make_project "$project_name" $with_strace "$iterations" "$build_path"
elif [ "$project_type" = "gradle" ]; then
  build_gradle_project "$project_name" "$with_strace" $iterations
elif [ "$project_type" = "sbuild" ]; then
  build_sbuild_project "$project_name" "$with_strace" $iterations
elif [ "$project_type" = "mkcheck" ]; then
  build_mkcheck_project "$project_name" "$with_strace" $iterations "$build_path"
elif [ "$project_type" = "sbuild-mkcheck" ]; then
  build_sbuild_mkcheck_project "$project_name" "$with_strace" $iterations
fi


if [ $? -ne 0 ]; then
  exit 1
fi


if [ $offline -eq 1 ]; then
  buildfs_offline "$project_name" $iterations "$project_type"
fi
exit $?
