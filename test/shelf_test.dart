import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:labos_unit8_exercise/shelf/api_exception.dart';
import 'package:labos_unit8_exercise/shelf/book.dart';
import 'package:labos_unit8_exercise/shelf/omdb_api.dart';
import 'package:labos_unit8_exercise/shelf/open_library_api.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('Book', () {
    test('reads the work id, author and cover', () {
      final book = Book.fromJson({
        'key': '/works/OL27482W',
        'title': 'The Hobbit',
        'author_name': ['J.R.R. Tolkien'],
        'first_publish_year': 1937,
        'cover_i': 123,
      });
      expect(book.workId, 'OL27482W');
      expect(book.firstAuthor, 'J.R.R. Tolkien');
      expect(book.coverUrl, 'https://covers.openlibrary.org/b/id/123-M.jpg');
    });

    test('copes with a missing author and cover', () {
      final book = Book.fromJson({'key': '/works/OL1W', 'title': 'No Author'});
      expect(book.firstAuthor, isNull);
      expect(book.coverUrl, isNull);
    });
  });

  group('OpenLibraryApi', () {
    test('search sends the query and parses the books', () async {
      late Uri requested;
      final api = OpenLibraryApi(
        MockClient((request) async {
          requested = request.url;
          return jsonResponse({
            'docs': [
              {'key': '/works/OL27482W', 'title': 'The Hobbit'},
            ],
          });
        }),
      );

      final books = await api.search('hobbit');

      expect(requested.host, 'openlibrary.org');
      expect(requested.queryParameters['q'], 'hobbit');
      expect(books.single.title, 'The Hobbit');
    });

    test('details reads a description given as an object', () async {
      final api = OpenLibraryApi(
        MockClient(
          (_) async => jsonResponse({
            'title': 'The Hobbit',
            'description': {'type': '/type/text', 'value': 'A hobbit goes.'},
            'covers': [-1],
          }),
        ),
      );

      final details = await api.details('OL27482W');

      expect(details.summary, 'A hobbit goes.');
      expect(details.imageUrl, isNull);
    });

    test('details reads a description given as text, with a cover', () async {
      final api = OpenLibraryApi(
        MockClient(
          (_) async => jsonResponse({
            'title': 'The Hobbit',
            'description': 'Plain text.',
            'covers': [555],
          }),
        ),
      );

      final details = await api.details('OL27482W');

      expect(details.summary, 'Plain text.');
      expect(details.imageUrl, 'https://covers.openlibrary.org/b/id/555-L.jpg');
    });

    test('a 404 becomes an ApiException', () async {
      final api = OpenLibraryApi(MockClient((_) async => jsonResponse({}, 404)));

      await expectLater(
        api.search('abc'),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', contains('404')),
        ),
      );
    });

    test('no internet becomes an ApiException', () async {
      final api = OpenLibraryApi(
        MockClient((_) async => throw http.ClientException('offline')),
      );

      await expectLater(
        api.search('abc'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('No connection'),
          ),
        ),
      );
    });
  });

  group('OmdbApi', () {
    test('search sends the key and treats N/A as no poster', () async {
      late Uri requested;
      final api = OmdbApi(
        apiKey: 'test-key',
        client: MockClient((request) async {
          requested = request.url;
          return jsonResponse({
            'Response': 'True',
            'Search': [
              {
                'Title': 'Interstellar',
                'Year': '2014',
                'imdbID': 'tt0816692',
                'Type': 'movie',
                'Poster': 'N/A',
              },
            ],
          });
        }),
      );

      final movies = await api.search('inter');

      expect(requested.queryParameters['apikey'], 'test-key');
      expect(requested.queryParameters['s'], 'inter');
      expect(movies.single.title, 'Interstellar');
      expect(movies.single.poster, isNull);
    });

    test('"Movie not found!" is an empty list, not an error', () async {
      final api = OmdbApi(
        apiKey: 'test-key',
        client: MockClient(
          (_) async => jsonResponse({
            'Response': 'False',
            'Error': 'Movie not found!',
          }),
        ),
      );

      expect(await api.search('zzzzzz'), isEmpty);
    });

    test('a bad key is an ApiException with OMDb\'s message', () async {
      final api = OmdbApi(
        apiKey: 'bad',
        client: MockClient(
          (_) async => jsonResponse({
            'Response': 'False',
            'Error': 'Invalid API key!',
          }, 401),
        ),
      );

      await expectLater(
        api.search('abc'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Invalid API key!',
          ),
        ),
      );
    });
  });
}
