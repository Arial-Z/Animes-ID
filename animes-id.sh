#!/bin/bash

SCRIPT_FOLDER=$(dirname $(readlink -f $0))

if [ ! -d $SCRIPT_FOLDER/tmp ]
then
	mkdir $SCRIPT_FOLDER/tmp
else
    rm $SCRIPT_FOLDER/tmp/*
fi

function missing_multiples_movies () {
    if  echo $imdbid | grep ,
    then
        columns_total_mumbers=$(echo "$imdbid" | awk -F"," '{print NF}')
        columns_mumbers=1
        missing_movies=""
        while [ $columns_mumbers -le $columns_total_mumbers ];
        do
            current_movie=$(echo "$imdbid" | awk -v columns_mumbers=$columns_mumbers -F"," '{print $columns_mumbers}')
            if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/override-movies.tsv | grep -w $current_movie
            then
                missing_movies=$(printf "$missing_movies$current_movie," )
            fi
        ((columns_mumbers++))
        done
        if [[ -n "$missing_movies" ]]
        then
            printf "Anidb : $anidbid missing multiples movies $missing_movies\n" >> missing-multiples-movies.txt
        fi
        imdbid=$(echo "$imdbid" | awk -F"," '{print $1}')
    fi
}


function read_dom () {
	local IFS=\>
	read -d \< ENTITY CONTENT
	local RET=$?
	TAG_NAME=${ENTITY%% *}
	ATTRIBUTES=${ENTITY#* }
	return $RET
}

function parse_dom () {
	if [[ $TAG_NAME = "anime" ]] ; then
		eval local $ATTRIBUTES
		if [[ -n "$tvdbid" ]] && [ "$tvdbid" -eq "$tvdbid" ] 2>/dev/null
		then
			if [[ "$defaulttvdbseason" == a ]]
			then
				defaulttvdbseason=-1
			fi
			if [[ -z "$episodeoffset" ]]
			then
				episodeoffset=0
			fi
			line=$(grep -w -n "https://anidb.net/anime/$anidbid"  $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | cut -d : -f 1)
			if [[ -n "$line" ]]
			then
				malid=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/myanimelist.net\/anime\/)(\d+)")
				anilistid=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/anilist.co\/anime\/)(\d+)")
			fi
			printf "$tvdbid\t$defaulttvdbseason\t$episodeoffset\t$anidbid\t$malid\t$anilistid\n" >> $SCRIPT_FOLDER/tmp/list-animes-id.tsv
		fi
		if [[ -n "$imdbid" ]] && [[ $imdbid != "unknown" ]]
		then
			missing_multiples_movies
			if ! awk -F"\t" '{print $1}' $SCRIPT_FOLDER/tmp/list-movies-id.tsv | grep -w $imdbid
			then
				line=$(grep -w -n "https://anidb.net/anime/$anidbid"  $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | cut -d : -f 1)
				if [[ -n "$line" ]]
				then
					malid=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/myanimelist.net\/anime\/)(\d+)")
					anilistid=$(awk -v line=$line -F"\t" 'NR==line' $SCRIPT_FOLDER/tmp/anime-offline-database.tsv | grep -oP "(?<=https:\/\/anilist.co\/anime\/)(\d+)")
				fi
				printf "$imdbid\t$anidbid\t$malid\t$anilistid\n" >> $SCRIPT_FOLDER/tmp/list-movies-id.tsv
			fi
		fi
	fi
}

wget -O $SCRIPT_FOLDER/tmp/anime-list-master.xml "https://raw.githubusercontent.com/Anime-Lists/anime-lists/master/anime-list-master.xml"
wget -O $SCRIPT_FOLDER/tmp/anime-offline-database.json "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json"

tail -n +2 $SCRIPT_FOLDER/override-movies.tsv > $SCRIPT_FOLDER/tmp/list-movies-id.tsv
printf "" > $SCRIPT_FOLDER/missing-multiples-movies.txt

jq ".data[].sources| @tsv" -r $SCRIPT_FOLDER/tmp/anime-offline-database.json > $SCRIPT_FOLDER/tmp/anime-offline-database.tsv

while read_dom
do
	parse_dom
done < $SCRIPT_FOLDER/tmp/anime-list-master.xml

cat $SCRIPT_FOLDER/tmp/list-animes-id.tsv | jq -s  --slurp --raw-input --raw-output 'split("\n") | .[0:-1] | map(split("\t")) |
	map({"tvdb_id": .[0],
	"tvdb_season": .[1],
	"tvdb_epoffset": .[2],
	"anidb_id": .[3],
	"mal_id": .[4],
	"anilist_id": .[5]})' > $SCRIPT_FOLDER/list-animes-id.json

cat $SCRIPT_FOLDER/tmp/list-movies-id.tsv | jq -s  --slurp --raw-input --raw-output 'split("\n") | .[0:-1] | map(split("\t")) |
	map({"imdb_id": .[0],
	"anidb_id": .[1],
	"mal_id": .[2],
	"anilist_id": .[3]})' > $SCRIPT_FOLDER/list-movies-id.json
