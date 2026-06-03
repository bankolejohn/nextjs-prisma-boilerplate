import { useQuery } from 'react-query';
import { PostWithAuthor } from 'types/models/Post';
import { AxiosError } from 'axios';
import { Routes } from 'lib-client/constants';
import axiosInstance from 'lib-client/react-query/axios';
import QueryKeys from 'lib-client/react-query/queryKeys';

const getPost = async (id: number) => {
  const { data } = await axiosInstance.get<PostWithAuthor>(`${Routes.API.POSTS}${id}`);
  return data;
};

export const usePost = (id: number) => {
  const query = useQuery<PostWithAuthor, AxiosError>(
    [QueryKeys.POST, id],
    () => getPost(id),
    {
      enabled: !isNaN(id), // important for 0
      staleTime: 30 * 1000, // 30s — post content rarely changes mid-session
      cacheTime: 5 * 60 * 1000, // keep in cache for 5 minutes after unmount
    }
  );

  return query;
};
