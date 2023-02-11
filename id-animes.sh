#!/bin/bash

SCRIPT_FOLDER=$(dirname $(readlink -f $0))
wget -O $SCRIPT_FOLDER/anime-list-master.xml "https://raw.githubusercontent.com/Anime-Lists/anime-lists/master/anime-list-master.xml"
wget -O $SCRIPT_FOLDER/anime-offline-database.json "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json"

if [  -f $SCRIPT_FOLDER/list-animes-id.tsv ]
then
	rm $SCRIPT_FOLDER/list-animes-id.tsv
fi
if [  -f $SCRIPT_FOLDER/list-movies-id.tsv ]
then
	rm $SCRIPT_FOLDER/list-movies-id.tsv
fi

read_dom () {
	local IFS=\>
	read -d \< ENTITY CONTENT
	local RET=$?
	TAG_NAME=${ENTITY%% *}
	ATTRIBUTES=${ENTITY#* }
	return $RET
}

parse_dom () {
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
			line=$(grep -w -n "https://anidb.net/anime/$anidbid"  $SCRIPT_FOLDER/anime-offline-database.tsv | cut -d : -f 1)
			if [[ -n "$line" ]]
			then
				malid=$(awk -v line=$line -F"\t" 'NR==line' anime-offline-database.tsv | grep -oP "(?<=https:\/\/myanimelist.net\/anime\/)(\d+)")
				anilistid=$(awk -v line=$line -F"\t" 'NR==line' anime-offline-database.tsv | grep -oP "(?<=https:\/\/anilist.co\/anime\/)(\d+)")
			fi
			printf "$tvdbid\t$defaulttvdbseason\t$episodeoffset\t$anidbid\t$malid\t$anilistid\n" >> $SCRIPT_FOLDER/list-animes-id.tsv
		fi
		if [[ -n "$imdbid" ]]
		then
			line=$(grep -w -n "https://anidb.net/anime/$anidbid"  $SCRIPT_FOLDER/anime-offline-database.tsv | cut -d : -f 1)
			if [[ -n "$line" ]]
			then
				malid=$(awk -v line=$line -F"\t" 'NR==line' anime-offline-database.tsv | grep -oP "(?<=https:\/\/myanimelist.net\/anime\/)(\d+)")
				anilistid=$(awk -v line=$line -F"\t" 'NR==line' anime-offline-database.tsv | grep -oP "(?<=https:\/\/anilist.co\/anime\/)(\d+)")
			fi
			printf "$imdbid\t$anidbid\t$malid\t$anilistid\n" >> $SCRIPT_FOLDER/list-movies-id.tsv
		fi

	fi
}

jq ".data[].sources| @tsv" -r $SCRIPT_FOLDER/anime-offline-database.json > $SCRIPT_FOLDER/anime-offline-database.tsv

while read_dom
do
	parse_dom
done < $SCRIPT_FOLDER/anime-list-master.xml

cat $SCRIPT_FOLDER/list-animes-id.tsv | jq -s  --slurp --raw-input --raw-output 'split("\n") | .[1:-1] | map(split("\t")) |
	map({"tvdb_id": .[0],
	"tvdb_season": .[1],
	"tvdb_epoffset": .[2],
	"anidb_id": .[3],
	"mal_id": .[4],
	"anilist_id": .[5]})' > $SCRIPT_FOLDER/list-animes-id.json

cat $SCRIPT_FOLDER/list-movies-id.tsv | jq -s  --slurp --raw-input --raw-output 'split("\n") | .[1:-1] | map(split("\t")) |
	map({"imdb_id": .[0],
	"anidb_id": .[1],
	"mal_id": .[2],
	"anilist_id": .[3]})' > $SCRIPT_FOLDER/list-movies-id.json
