#include <dplyr.h>

using namespace Rcpp ;
using namespace dplyr ;

template <typename Dots>
List rbind__impl( Dots dots ){
    int ndata = dots.size() ;
    int n = 0 ;
    for( int i=0; i<ndata; i++) {
      DataFrame df = dots[i] ;
      if( df.size() ) n += df.nrows() ;
    }
    std::vector<Collecter*> columns ;
    std::vector<String> names ;
    int k=0 ;
    for( int i=0; i<ndata; i++){
        Rcpp::checkUserInterrupt() ;
        
        DataFrame df = dots[i] ;
        if( !df.size() || !Rf_length(df[0]) ) continue ;
            
        DataFrameVisitors visitors( df, df.names() ) ;
        int nrows = df.nrows() ;

        CharacterVector df_names = df.names() ;
        for( int j=0; j<df.size(); j++){
            SEXP source = df[j] ;
            String name = df_names[j] ;

            Collecter* coll = 0;
            size_t index = 0 ;
            for( ; index < names.size(); index++){
                if( name == names[index] ){
                    coll = columns[index] ;
                    break ;
                }
            }
            if( ! coll ){
                coll = collecter( source, n ) ;
                columns.push_back( coll );
                names.push_back(name) ;
            }

            if( coll->compatible(source) ){
                // if the current source is compatible, collect
                coll->collect( SlicingIndex( k, nrows), source ) ;

            } else if( coll->can_promote(source) ) {
                // setup a new Collecter
                Collecter* new_collecter = promote_collecter(source, n, coll ) ;

                // import data from this chunk
                new_collecter->collect( SlicingIndex( k, nrows), source ) ;

                // import data from previous collecter
                new_collecter->collect( SlicingIndex(0, k), coll->get() ) ;

                // dispose the previous collecter and keep the new one.
                delete coll ;
                columns[index] = new_collecter ;

            } else {
                std::stringstream msg ;
                std::string column_name(name) ;
                msg << "incompatible type ("
                    << "data index: "
                    << (i+1)
                    << ", column: '"
                    << column_name
                    << "', was collecting: "
                    << coll->describe()
                    << " ("
                    << DEMANGLE(*coll)
                    << ")"
                    << ", incompatible with data of type: "
                    << get_single_class(source) ;

                stop( msg.str() ) ;
            }

        }

        k += nrows ;
    }

    int nc = columns.size() ;
    List out(nc) ;
    CharacterVector out_names(nc) ;
    for( int i=0; i<nc; i++){
        out[i] = columns[i]->get() ;
        out_names[i] = names[i] ;
    }
    out.attr( "names" ) = out_names ;
    delete_all( columns ) ;
    set_rownames( out, n );
    out.attr( "class" ) = "data.frame" ;

    return out ;
}

//' @export
//' @rdname rbind
// [[Rcpp::export]]
List rbind_all( StrictListOf<DataFrame, NULL_or_Is<DataFrame> > dots ){
    return rbind__impl(dots) ;
}

// [[Rcpp::export]]
List rbind_list__impl( DotsOf<DataFrame> dots ){
    return rbind__impl(dots) ;
}

template <typename Dots>
List cbind__impl( Dots dots ){
  int n = dots.size() ;
  
  // first check that the number of rows is the same
  DataFrame df = dots[0] ;
  int nrows = df.nrows() ;
  int nv = df.size() ;
  for( int i=1; i<n; i++){
    DataFrame current = dots[i] ;
    if( current.nrows() != nrows ){
      std::stringstream ss ;
      ss << "incompatible number of rows (" 
         << current.size()
         << ", expecting "
         << nrows 
      ;
      stop( ss.str() ) ;
    }
    nv += current.size() ;
  }
  
  // collect columns
  List out(nv) ;
  CharacterVector out_names(nv) ;
  
  // then do the subsequent dfs
  for( int i=0, k=0 ; i<n; i++){
      Rcpp::checkUserInterrupt() ;
    
      DataFrame current = dots[i] ;
      CharacterVector current_names = current.names() ;
      int nc = current.size() ;
      for( int j=0; j<nc; j++, k++){
          out[k] = shared_SEXP(current[j]) ;
          out_names[k] = current_names[j] ;
      }
  }
  out.names() = out_names ;
  set_rownames( out, nrows ) ;
  out.attr( "class") = "data.frame" ;
  return out ;
}

// [[Rcpp::export]]
List cbind_list__impl( DotsOf<DataFrame> dots ){
  return cbind__impl( dots ) ;  
}

// [[Rcpp::export]]
List cbind_all( StrictListOf<DataFrame, NULL_or_Is<DataFrame> > dots ){
    return cbind__impl( dots ) ;  
}

